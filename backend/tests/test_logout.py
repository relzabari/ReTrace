"""Verify logout delegation, scope isolation, failures and refresh-token rejection.

Supabase is simulated; these tests never use real accounts or credentials.
"""
from types import SimpleNamespace

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api import auth_routes
from app.core import auth
from app.db.session import get_db


@pytest.fixture
def logout_env(monkeypatch):
    app = FastAPI()
    app.include_router(auth_routes.router)
    app.dependency_overrides[get_db] = lambda: None
    sessions = {'phone': True, 'browser': True, 'other-user': True}
    calls = []
    responses = []

    def provider(method, path, *, access_token=None, admin=False, json=None):
        calls.append((method, path, access_token, admin))
        if responses:
            item = responses.pop(0)
            if isinstance(item, Exception):
                raise item
            return httpx.Response(item)
        if path.startswith('/logout?scope='):
            if access_token not in sessions or not sessions[access_token]:
                return httpx.Response(401)
            if path.endswith('global'):
                owner_sessions = ['other-user'] if access_token == 'other-user' else ['phone', 'browser']
                for session in owner_sessions:
                    sessions[session] = False
            else:
                sessions[access_token] = False
            return httpx.Response(204)
        if path == '/token?grant_type=refresh_token':
            token = json['refresh_token'].removeprefix('refresh-')
            if not sessions.get(token):
                return httpx.Response(400)
            return httpx.Response(200, json={
                'access_token': token, 'refresh_token': 'refresh-'+token,
                'user': {'id': 'unused'}, 'expires_in': 600,
            })
        raise AssertionError((method, path))

    monkeypatch.setattr(auth_routes, 'supabase_request', provider)
    monkeypatch.setattr(auth_routes, 'sync_user', lambda *_: SimpleNamespace(
        id='user', email='user@example.com', role='USER', is_active=True))
    with TestClient(app) as client:
        yield client, sessions, calls, responses


def logout(client, token='phone', scope=None):
    path = '/api/v1/auth/logout' + (f'?scope={scope}' if scope else '')
    return client.post(path, headers={'Authorization': 'Bearer '+token})


def refresh(client, token):
    return client.post('/api/v1/auth/refresh', json={'refresh_token': 'refresh-'+token})


def test_local_is_default_and_does_not_revoke_other_devices(logout_env):
    client, sessions, calls, _ = logout_env
    assert logout(client).status_code == 204
    assert calls[0] == ('POST', '/logout?scope=local', 'phone', False)
    assert refresh(client, 'phone').status_code == 401
    assert refresh(client, 'browser').status_code == 200
    assert sessions['other-user']


def test_global_revokes_all_own_refresh_tokens_but_not_other_users(logout_env):
    client, sessions, calls, _ = logout_env
    assert logout(client, scope='global').status_code == 204
    assert calls[0] == ('POST', '/logout?scope=global', 'phone', False)
    assert refresh(client, 'phone').status_code == 401
    assert refresh(client, 'browser').status_code == 401
    assert sessions['other-user']


@pytest.mark.parametrize('scope', ['others', 'admin', 'global&user=other', ''])
def test_rejects_unknown_scopes_without_contacting_supabase(logout_env, scope):
    client, _, calls, _ = logout_env
    response = client.post('/api/v1/auth/logout', params={'scope': scope}, headers={'Authorization': 'Bearer phone'})
    assert response.status_code == 422
    assert not calls


def test_anonymous_and_invalid_tokens_cannot_sign_out_accounts(logout_env):
    client, sessions, calls, _ = logout_env
    assert client.post('/api/v1/auth/logout').status_code == 401
    assert not calls
    assert logout(client, token='forged', scope='global').status_code == 401
    assert all(sessions.values())


@pytest.mark.parametrize('provider_status, expected', [(401,401),(403,401),(429,429),(500,503),(200,503)])
def test_failures_are_not_reported_as_success(logout_env, provider_status, expected):
    client, _, _, responses = logout_env
    responses.append(provider_status)
    assert logout(client).status_code == expected


def test_provider_network_failure_does_not_claim_revocation(logout_env):
    client, _, _, responses = logout_env
    responses.append(HTTPException(503, 'Authentication service is unavailable'))
    assert logout(client).status_code == 503


def test_repeated_logout_is_not_silently_treated_as_global_success(logout_env):
    client, _, _, _ = logout_env
    assert logout(client).status_code == 204
    assert logout(client, scope='global').status_code == 401


def test_authentication_still_checks_supabase_instead_of_decoding_unverified_tokens(monkeypatch):
    observed = []
    def provider(method, path, **kwargs):
        observed.append((method, path, kwargs))
        return httpx.Response(401)
    monkeypatch.setattr(auth, 'supabase_request', provider)
    with pytest.raises(HTTPException) as error:
        auth.get_current_user(auth.HTTPAuthorizationCredentials(scheme='Bearer', credentials='expired-or-revoked'), None)
    assert error.value.status_code == 401
    assert observed[0][:2] == ('GET', '/user')
