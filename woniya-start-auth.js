(function(global){
  'use strict';

  if (global.WoniyaStartAuth) {
    throw new Error('window.WoniyaStartAuth is already defined.');
  }

  var UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  var SLUG_PATTERN = /^[a-z0-9-]+$/;
  var TEMPLATE_PATHS = Object.freeze({
    sunshine: '/template-sunshine.html',
    forest: '/template-forest.html',
    carnival: '/template-carnival.html',
    gallery: '/template-gallery.html'
  });
  var ROUTE_PATHS = Object.freeze({
    centerAdmin: '/admin.html',
    classAdmin: '/class-admin.html',
    parentClass: '/parent.html'
  });

  function authError(code, message, cause){
    var error = new Error(message);
    error.code = code;
    if (cause !== undefined) error.cause = cause;
    return error;
  }

  function isPlainObject(value){
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    var prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null;
  }

  function normalizeUuid(value){
    if (typeof value !== 'string') return '';
    var normalized = value.trim().toLowerCase();
    return UUID_PATTERN.test(normalized) ? normalized : '';
  }

  function sessionUserId(session){
    if (session == null) return '';
    if (!session.user || typeof session.user !== 'object') {
      throw authError('INVALID_SESSION', 'The authentication session has an invalid user.');
    }
    var userId = normalizeUuid(session.user.id);
    if (!userId) {
      throw authError('INVALID_SESSION', 'The authentication session has an invalid user id.');
    }
    return userId;
  }

  function normalizeUuidArray(value, roleName){
    if (!Array.isArray(value)) {
      throw authError('INVALID_ROLE_RESPONSE', roleName + ' role response must be an array.');
    }

    var seen = new Set();
    var normalized = [];
    value.forEach(function(item){
      var id = normalizeUuid(item);
      if (!id) {
        throw authError('INVALID_ROLE_RESPONSE', roleName + ' role response contains an invalid UUID.');
      }
      if (seen.has(id)) return;
      seen.add(id);
      normalized.push(id);
    });
    return normalized;
  }

  function normalizeParentSummaries(value){
    if (!Array.isArray(value)) {
      throw authError('INVALID_ROLE_RESPONSE', 'Parent role response must be an array.');
    }

    var seen = new Set();
    var normalized = [];
    value.forEach(function(item){
      if (!isPlainObject(item)) {
        throw authError('INVALID_ROLE_RESPONSE', 'Parent role response contains an invalid summary.');
      }

      var id = normalizeUuid(item.id);
      var validName = item.name == null || typeof item.name === 'string';
      var validAgeLabel = item.age_label == null || typeof item.age_label === 'string';
      var validEnrolled = item.enrolled == null ||
        (Number.isInteger(item.enrolled) && item.enrolled >= 0);
      if (!id || !validName || !validAgeLabel || !validEnrolled) {
        throw authError('INVALID_ROLE_RESPONSE', 'Parent role response contains invalid summary fields.');
      }
      if (seen.has(id)) return;
      seen.add(id);
      normalized.push({
        id: id,
        name: item.name == null ? null : item.name,
        age_label: item.age_label == null ? null : item.age_label,
        enrolled: item.enrolled == null ? null : item.enrolled
      });
    });
    return normalized;
  }

  function validateClient(client){
    if (!client || typeof client !== 'object' ||
        !client.auth || typeof client.auth.getSession !== 'function' ||
        typeof client.auth.onAuthStateChange !== 'function' ||
        typeof client.rpc !== 'function') {
      throw authError('INVALID_CLIENT', 'A compatible Supabase client is required.');
    }
  }

  function normalizeSlug(value){
    if (typeof value !== 'string') {
      throw authError('INVALID_ROUTE_PARAMETER', 'A center slug is required.');
    }
    var slug = value.trim();
    if (!slug || !SLUG_PATTERN.test(slug)) {
      throw authError('INVALID_ROUTE_PARAMETER', 'The center slug is invalid.');
    }
    return slug;
  }

  function sameOriginPath(path, searchParams){
    if (!global.location || typeof global.location.origin !== 'string' || !global.location.origin) {
      throw authError('INVALID_ORIGIN', 'The current page origin is unavailable.');
    }
    var target = new URL(path, global.location.origin);
    Object.keys(searchParams || {}).forEach(function(key){
      target.searchParams.set(key, searchParams[key]);
    });
    if (target.origin !== global.location.origin || target.pathname !== path) {
      throw authError('UNSAFE_ROUTE', 'Only allowlisted same-origin routes are supported.');
    }
    return target.pathname + target.search;
  }

  function buildInternalUrl(kind, options){
    var config = options && typeof options === 'object' ? options : {};

    if (kind === 'centerAdmin') {
      return sameOriginPath(ROUTE_PATHS.centerAdmin, { slug:normalizeSlug(config.slug) });
    }
    if (kind === 'classAdmin' || kind === 'parentClass') {
      var classId = normalizeUuid(config.classId);
      if (!classId) {
        throw authError('INVALID_ROUTE_PARAMETER', 'A valid class UUID is required.');
      }
      return sameOriginPath(ROUTE_PATHS[kind], { class_id:classId });
    }
    if (kind === 'centerHomepage') {
      var templatePath = TEMPLATE_PATHS[config.template];
      if (!templatePath) {
        throw authError('INVALID_ROUTE_PARAMETER', 'The center template is not allowlisted.');
      }
      return sameOriginPath(templatePath, { slug:normalizeSlug(config.slug) });
    }
    throw authError('INVALID_ROUTE', 'The requested internal route is not allowlisted.');
  }

  function createController(client){
    validateClient(client);

    var requestGeneration = 0;
    var observedUserId;

    async function readSession(){
      var result = await client.auth.getSession();
      if (!result || typeof result !== 'object' || result.error) {
        throw authError(
          'SESSION_REQUEST_FAILED',
          'The authentication session could not be read.',
          result && result.error
        );
      }
      if (!result.data || !Object.prototype.hasOwnProperty.call(result.data, 'session')) {
        throw authError('INVALID_SESSION_RESPONSE', 'The authentication session response is invalid.');
      }
      var session = result.data.session;
      sessionUserId(session);
      return session;
    }

    function observeIdentity(session, invalidateOnChange){
      var nextUserId = sessionUserId(session);
      if (invalidateOnChange && observedUserId !== undefined && observedUserId !== nextUserId) {
        requestGeneration += 1;
      }
      observedUserId = nextUserId;
      return nextUserId;
    }

    async function getSession(){
      var session = await readSession();
      observeIdentity(session, true);
      return session;
    }

    function invalidate(){
      requestGeneration += 1;
    }

    function subscribe(listener){
      if (typeof listener !== 'function') {
        throw authError('INVALID_LISTENER', 'An authentication listener function is required.');
      }

      var subscriptionResult = client.auth.onAuthStateChange(function(event, session){
        observeIdentity(session, true);
        listener(event, session);
      });
      var subscription = subscriptionResult && subscriptionResult.data
        ? subscriptionResult.data.subscription
        : null;
      if (!subscription || typeof subscription.unsubscribe !== 'function') {
        throw authError('SUBSCRIBE_FAILED', 'The authentication subscription could not be created.');
      }

      var isUnsubscribed = false;
      return function unsubscribe(){
        if (isUnsubscribed) return;
        isUnsubscribed = true;
        subscription.unsubscribe();
      };
    }

    function staleRequestError(){
      return authError('STALE_REQUEST', 'A newer authentication request replaced this request.');
    }

    function ensureCurrentRequest(generation, userId){
      if (generation !== requestGeneration || observedUserId !== userId) {
        throw staleRequestError();
      }
    }

    async function loadConnections(){
      var generation = ++requestGeneration;
      var observedUserIdAtStart = observedUserId;
      var session = await readSession();
      if (generation !== requestGeneration || observedUserId !== observedUserIdAtStart) {
        throw staleRequestError();
      }

      var userId = sessionUserId(session);
      if (!userId) {
        observedUserId = '';
        throw authError('AUTH_REQUIRED', 'An authenticated user is required.');
      }
      observedUserId = userId;

      var results;
      try {
        results = await Promise.all([
          client.rpc('my_owned_center_ids'),
          client.rpc('my_teaching_class_ids'),
          client.rpc('get_my_approved_class_summaries')
        ]);
      } catch (error) {
        ensureCurrentRequest(generation, userId);
        throw authError('ROLE_REQUEST_FAILED', 'One or more role requests failed.', error);
      }
      ensureCurrentRequest(generation, userId);

      if (!Array.isArray(results) || results.length !== 3) {
        throw authError('INVALID_ROLE_RESPONSE', 'The role request response is invalid.');
      }

      var roleErrors = {};
      if (!results[0] || results[0].error) roleErrors.owner = results[0] && results[0].error;
      if (!results[1] || results[1].error) roleErrors.teacher = results[1] && results[1].error;
      if (!results[2] || results[2].error) roleErrors.parent = results[2] && results[2].error;
      if (Object.keys(roleErrors).length) {
        var requestError = authError('ROLE_REQUEST_FAILED', 'One or more role requests failed.');
        requestError.roleErrors = roleErrors;
        throw requestError;
      }

      var roleResult = {
        userId: userId,
        ownerCenterIds: normalizeUuidArray(results[0].data, 'Owner'),
        teacherClassIds: normalizeUuidArray(results[1].data, 'Teacher'),
        parentClassSummaries: normalizeParentSummaries(results[2].data)
      };

      var currentSession = await readSession();
      var currentUserId = sessionUserId(currentSession);
      if (currentUserId !== userId) {
        observedUserId = currentUserId;
        requestGeneration += 1;
        throw staleRequestError();
      }
      ensureCurrentRequest(generation, userId);
      return roleResult;
    }

    return Object.freeze({
      getSession: getSession,
      subscribe: subscribe,
      loadConnections: loadConnections,
      invalidate: invalidate
    });
  }

  global.WoniyaStartAuth = Object.freeze({
    createController: createController,
    buildInternalUrl: buildInternalUrl
  });
})(window);
