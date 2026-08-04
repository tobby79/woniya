(function (root) {
  'use strict';

  if (!root || 'WoniyaInquiryRealtime' in root) {
    return;
  }

  var DEFAULT_DEBOUNCE_MS = 250;
  var MAX_RECENT_MESSAGE_IDS = 1000;
  var SUPPORTED_STATUSES = {
    SUBSCRIBED: true,
    CHANNEL_ERROR: true,
    TIMED_OUT: true,
    CLOSED: true
  };

  function isPresent(value) {
    return value !== null && value !== undefined && String(value).trim() !== '';
  }

  function copyContext(context) {
    if (!context) {
      return null;
    }

    return {
      userId: context.userId,
      classId: context.classId,
      role: context.role,
      contextVersion: context.contextVersion
    };
  }

  function normalizeContext(viewerKind, context) {
    if (!context || !isPresent(context.userId) || !isPresent(context.classId)) {
      return null;
    }

    if (!isPresent(context.contextVersion)) {
      return null;
    }

    if (viewerKind === 'parent' && context.role !== 'parent') {
      return null;
    }

    if (
      viewerKind === 'staff' &&
      context.role !== 'teacher' &&
      context.role !== 'owner'
    ) {
      return null;
    }

    var versionType = typeof context.contextVersion;
    if (
      versionType !== 'string' &&
      versionType !== 'number' &&
      versionType !== 'boolean'
    ) {
      return null;
    }

    return {
      userId: String(context.userId),
      classId: String(context.classId),
      role: context.role,
      contextVersion: context.contextVersion
    };
  }

  function makeChannelKey(viewerKind, context) {
    return JSON.stringify([
      viewerKind,
      context.userId,
      context.role,
      context.classId
    ]);
  }

  function createManager(options) {
    if (!options || !options.supabase) {
      throw new TypeError('A Supabase client is required.');
    }

    if (
      typeof options.supabase.channel !== 'function' ||
      typeof options.supabase.removeChannel !== 'function'
    ) {
      throw new TypeError('The Supabase client does not support Realtime channels.');
    }

    if (options.viewerKind !== 'parent' && options.viewerKind !== 'staff') {
      throw new TypeError('viewerKind must be parent or staff.');
    }

    if (typeof options.onRefreshNeeded !== 'function') {
      throw new TypeError('onRefreshNeeded must be a function.');
    }

    if (typeof options.onStatusChange !== 'function') {
      throw new TypeError('onStatusChange must be a function.');
    }

    var debounceMs = DEFAULT_DEBOUNCE_MS;
    if (options.debounceMs !== undefined) {
      if (
        typeof options.debounceMs !== 'number' ||
        !Number.isFinite(options.debounceMs) ||
        options.debounceMs < 0
      ) {
        throw new TypeError('debounceMs must be a non-negative finite number.');
      }
      debounceMs = options.debounceMs;
    }

    var supabase = options.supabase;
    var viewerKind = options.viewerKind;
    var onRefreshNeeded = options.onRefreshNeeded;
    var onStatusChange = options.onStatusChange;

    var contextToken = 0;
    var currentContext = null;
    var currentChannelKey = null;
    var currentChannel = null;
    var channelSequence = 0;

    var debounceTimer = null;
    var pendingInquiryIds = new Set();
    var pendingMessage = false;
    var pendingSubscribed = false;
    var refreshInFlight = false;
    var recentMessageIds = new Map();

    function hasPendingRefresh() {
      return pendingMessage || pendingSubscribed || pendingInquiryIds.size > 0;
    }

    function clearDebounceTimer() {
      if (debounceTimer !== null) {
        root.clearTimeout(debounceTimer);
        debounceTimer = null;
      }
    }

    function clearPendingRefresh() {
      clearDebounceTimer();
      pendingInquiryIds.clear();
      pendingMessage = false;
      pendingSubscribed = false;
    }

    function resetContextWork() {
      clearPendingRefresh();
      recentMessageIds.clear();
    }

    function safelyRemoveChannel(channelToRemove) {
      if (!channelToRemove) {
        return;
      }

      try {
        var removal = supabase.removeChannel(channelToRemove);
        if (removal && typeof removal.catch === 'function') {
          removal.catch(function () {});
        }
      } catch (ignoredError) {
        // Channel cleanup failures must not expose data or stop later cleanup.
      }
    }

    function notifyStatus(status) {
      var statusInfo = {
        status: status,
        viewerKind: viewerKind,
        channelKey: currentChannelKey,
        context: copyContext(currentContext)
      };

      try {
        onStatusChange(statusInfo);
      } catch (ignoredError) {
        // Consumer status handling is isolated from the channel lifecycle.
      }
    }

    function rememberMessageId(messageId) {
      if (recentMessageIds.has(messageId)) {
        return false;
      }

      recentMessageIds.set(messageId, true);
      if (recentMessageIds.size > MAX_RECENT_MESSAGE_IDS) {
        var oldest = recentMessageIds.keys().next();
        if (!oldest.done) {
          recentMessageIds.delete(oldest.value);
        }
      }
      return true;
    }

    function settleRefresh() {
      refreshInFlight = false;
      if (hasPendingRefresh()) {
        flushPending();
      }
    }

    function flushPending() {
      clearDebounceTimer();

      if (refreshInFlight || !currentContext || !hasPendingRefresh()) {
        return false;
      }

      var batchHasMessage = pendingMessage;
      var batch = {
        inquiryIds: Array.from(pendingInquiryIds),
        silent: !batchHasMessage,
        reason: batchHasMessage ? 'message' : 'subscribed',
        context: copyContext(currentContext)
      };

      pendingInquiryIds.clear();
      pendingMessage = false;
      pendingSubscribed = false;
      refreshInFlight = true;

      var refreshResult;
      try {
        refreshResult = onRefreshNeeded(batch);
      } catch (ignoredError) {
        settleRefresh();
        return true;
      }

      Promise.resolve(refreshResult).then(settleRefresh, settleRefresh);
      return true;
    }

    function scheduleFlush(expectedToken, expectedChannelKey) {
      clearDebounceTimer();
      debounceTimer = root.setTimeout(function () {
        debounceTimer = null;
        if (
          expectedToken !== contextToken ||
          expectedChannelKey !== currentChannelKey
        ) {
          return;
        }
        flushPending();
      }, debounceMs);
    }

    function queueSubscribedRefresh(expectedToken, expectedChannelKey) {
      pendingSubscribed = true;
      scheduleFlush(expectedToken, expectedChannelKey);
    }

    function queueMessageRefresh(
      inquiryId,
      expectedToken,
      expectedChannelKey
    ) {
      pendingInquiryIds.add(inquiryId);
      pendingMessage = true;
      scheduleFlush(expectedToken, expectedChannelKey);
    }

    function handleInsert(payload, expectedToken, expectedChannelKey) {
      if (
        expectedToken !== contextToken ||
        expectedChannelKey !== currentChannelKey ||
        !currentContext
      ) {
        return;
      }

      var newRecord = payload && payload.new;
      if (!newRecord) {
        return;
      }

      var message = {
        id: newRecord.id,
        inquiry_id: newRecord.inquiry_id,
        sender_id: newRecord.sender_id,
        sender_role: newRecord.sender_role,
        message_type: newRecord.message_type,
        created_at: newRecord.created_at
      };

      if (
        message.message_type !== 'message' ||
        !isPresent(message.id) ||
        !isPresent(message.inquiry_id)
      ) {
        return;
      }

      if (
        isPresent(message.sender_id) &&
        String(message.sender_id) === currentContext.userId
      ) {
        return;
      }

      if (
        viewerKind === 'parent' &&
        message.sender_role !== 'teacher' &&
        message.sender_role !== 'owner'
      ) {
        return;
      }

      if (viewerKind === 'staff' && message.sender_role !== 'parent') {
        return;
      }

      var messageId = String(message.id);
      if (!rememberMessageId(messageId)) {
        return;
      }

      queueMessageRefresh(
        String(message.inquiry_id),
        expectedToken,
        expectedChannelKey
      );
    }

    function subscribeForContext(expectedToken, expectedChannelKey) {
      var channelName = [
        'woniya-inquiry',
        viewerKind,
        expectedToken,
        ++channelSequence
      ].join(':');
      var subscribedRefreshQueued = false;
      var nextChannel = null;

      try {
        nextChannel = supabase.channel(channelName);
        currentChannel = nextChannel;

        nextChannel.on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'class_inquiry_messages',
            filter: 'message_type=eq.message'
          },
          function (payload) {
            if (
              expectedToken !== contextToken ||
              expectedChannelKey !== currentChannelKey ||
              nextChannel !== currentChannel
            ) {
              return;
            }
            handleInsert(payload, expectedToken, expectedChannelKey);
          }
        );

        nextChannel.subscribe(function (status) {
          if (
            expectedToken !== contextToken ||
            expectedChannelKey !== currentChannelKey ||
            nextChannel !== currentChannel ||
            !SUPPORTED_STATUSES[status]
          ) {
            return;
          }

          notifyStatus(status);
          if (status === 'SUBSCRIBED' && !subscribedRefreshQueued) {
            subscribedRefreshQueued = true;
            queueSubscribedRefresh(expectedToken, expectedChannelKey);
          }
        });
      } catch (ignoredError) {
        if (nextChannel === currentChannel) {
          currentChannel = null;
        }
        currentChannelKey = null;
        safelyRemoveChannel(nextChannel);
        notifyStatus('CHANNEL_ERROR');
      }
    }

    function sync(context) {
      var nextContext = normalizeContext(viewerKind, context);

      if (!nextContext) {
        contextToken += 1;
        resetContextWork();

        var invalidContextChannel = currentChannel;
        currentChannel = null;
        currentChannelKey = null;
        currentContext = null;
        safelyRemoveChannel(invalidContextChannel);
        notifyStatus('STOPPED');
        return false;
      }

      var nextChannelKey = makeChannelKey(viewerKind, nextContext);
      if (nextChannelKey === currentChannelKey && currentChannel) {
        currentContext = nextContext;
        return true;
      }

      contextToken += 1;
      resetContextWork();

      var previousChannel = currentChannel;
      currentChannel = null;
      currentChannelKey = null;
      currentContext = null;
      safelyRemoveChannel(previousChannel);

      currentContext = nextContext;
      currentChannelKey = nextChannelKey;
      subscribeForContext(contextToken, nextChannelKey);
      return currentChannel !== null;
    }

    function stop() {
      contextToken += 1;
      resetContextWork();

      var channelToRemove = currentChannel;
      currentChannel = null;
      currentChannelKey = null;
      currentContext = null;
      safelyRemoveChannel(channelToRemove);
      notifyStatus('STOPPED');
    }

    return Object.freeze({
      sync: sync,
      stop: stop,
      flush: flushPending
    });
  }

  root.WoniyaInquiryRealtime = Object.freeze({
    createManager: createManager
  });
})(typeof window !== 'undefined' ? window : null);
