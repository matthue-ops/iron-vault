/* UI/session gates only. RLS and RPC authorization must enforce every operation. */
(function (root) {
    'use strict';
    const roles = new Set(['super_admin', 'owner', 'staff', 'member']);
    const sessionKeys = [
        'ironvault_super_session', 'ironvault_active_member', 'ironvault_active_token',
        'ironvault_active_tenant_id', 'ironvault_active_role', 'ironvault_logged_user',
        'ironvault_admin_signed_out'
    ];
    const cacheKeys = ['ironvault_owners_db', 'ironvault_members_db'];
    function failure(code, message) {
        const error = new Error(message);
        error.code = code;
        return error;
    }
    async function requireRole(client, options) {
        const requested = options?.roles;
        if (!Array.isArray(requested) || requested.length === 0 || requested.some(r => !roles.has(r))) {
            throw failure('INVALID_ROLE_REQUEST', 'A valid portal role is required.');
        }
        const {data: identity, error: authError} = await client.auth.getUser();
        const user = identity?.user;
        if (authError || !user?.id) throw failure('AUTH_REQUIRED', 'Please sign in again.');
        const {data, error} = await client.from('iv_user_roles')
            .select('user_id,tenant_id,member_id,role').eq('user_id', user.id);
        if (error || !Array.isArray(data)) {
            throw failure('ROLE_LOOKUP_FAILED', 'Permissions could not be verified. Please retry.');
        }
        const matches = data.filter(row => {
            if (row.user_id !== user.id || !requested.includes(row.role)) return false;
            if (row.role === 'super_admin') {
                // Global authority is explicit, never inferred from another role or missing tenant.
                return row.tenant_id == null && (!options.tenantId || options.allowGlobalSuperAdmin === true);
            }
            if (!row.tenant_id || (options.tenantId && row.tenant_id !== options.tenantId)) return false;
            if (row.role === 'member' && !row.member_id) return false;
            return !options.memberId || row.member_id === options.memberId;
        });
        if (!matches.length) throw failure('ACCESS_DENIED', 'This account cannot access this portal or gym.');
        const global = matches.find(row => row.role === 'super_admin');
        if (global) return Object.freeze({...global});
        if (new Set(matches.map(row => row.tenant_id)).size !== 1) {
            throw failure('TENANT_REQUIRED', 'Open the specific gym link before continuing.');
        }
        const memberLinks = new Set(matches.filter(r => r.role === 'member').map(r => r.member_id));
        if (memberLinks.size > 1) throw failure('AMBIGUOUS_MEMBER', 'This membership needs administrator review.');
        // An explicit caller-specified role order handles owner/staff bindings in the same gym.
        matches.sort((a, b) => requested.indexOf(a.role) - requested.indexOf(b.role));
        return Object.freeze({...matches[0]});
    }
    function clearState(session, cache) {
        for (const key of sessionKeys) session?.removeItem(key);
        for (const key of cacheKeys) cache?.removeItem(key);
    }
    async function signOut(client, session, cache) {
        clearState(session, cache);
        try {
            const {error} = await client.auth.signOut({scope: 'local'});
            if (error) throw failure('SIGNOUT_FAILED', 'Sign-out could not be confirmed. Please retry.');
        } finally {
            clearState(session, cache);
        }
    }
    const api = Object.freeze({requireRole, clearState, signOut});
    root.IronVaultAuth = api;
    if (typeof module === 'object' && module.exports) module.exports = api;
})(globalThis);
