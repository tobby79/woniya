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
  var TERMINAL_STATUSES = {
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
    var currentChannelUsable = false;
    var currentChannelStatus = 'STOPPED';
    var channelSequence = 0;
    var channelsScheduledForRemoval = new WeakSet();

    var debounceTimer = null;
    var pendingInquiryIds = new Set();
    var pendingMessage = false;
    var pendingSubscribed = false;
    var pendingContextToken = null;
    var pendingChannelKey = null;
    var currentRefreshRun = null;
    var refreshRunSequence = 0;
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
      pendingContextToken = null;
      pendingChannelKey = null;
    }

    function resetContextWork() {
      clearPendingRefresh();
      recentMessageIds.clear();
      currentRefreshRun = null;
    }

    function safelyRemoveChannel(channelToRemove) {
      if (!channelToRemove) {
        return;
      }

      if (channelsScheduledForRemoval.has(channelToRemove)) {
        return;
      }
      channelsScheduledForRemoval.add(channelToRemove);

      try {
        var removal = supabase.removeChannel(channelToRemove);
        if (removal && typeof removal.catch === 'function') {
          removal.catch(function () {});
        }
      } catch (ignoredError) {
        // Channel cleanup failures must not expose data or stop later cleanup.
      }
    }

    function retireCurrentChannel(
      status,
      expectedToken,
      expectedChannelKey,
      expectedChannel
    ) {
      if (
        !TERMINAL_STATUSES[status] ||
        expectedToken !== contextToken ||
        expectedChannelKey !== currentChannelKey ||
        expectedChannel !== currentChannel
      ) {
        return false;
      }

      currentChannelUsable = false;
      currentChannelStatus = status;
      contextToken += 1;
      resetContextWork();
      currentChannel = null;
      safelyRemoveChannel(expectedChannel);
      notifyStatus(status);
      return true;
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

    function pendingRefreshBelongsTo(token, channelKey) {
      return pendingContextToken === token &&
        pendingChannelKey === channelKey &&
        hasPendingRefresh();
    }

    function preparePendingRefresh(expectedToken, expectedChannelKey) {
      if (
        expectedToken !== contextToken ||
        expectedChannelKey !== currentChannelKey ||
        !currentContext
      ) {
        return false;
      }

      if (
        pendingContextToken !== null &&
        (pendingContextToken !== expectedToken ||
          pendingChannelKey !== expectedChannelKey)
      ) {
        clearPendingRefresh();
      }

      pendingContextToken = expectedToken;
      pendingChannelKey = expectedChannelKey;
      return true;
    }

    function settleRefresh(run) {
      if (
        currentRefreshRun !== run ||
        run.token !== contextToken ||
        run.channelKey !== currentChannelKey
      ) {
        return;
      }

      currentRefreshRun = null;
      if (pendingRefreshBelongsTo(run.token, run.channelKey)) {
        flushPending();
      }
    }

    function flushPending() {
      clearDebounceTimer();

      if (!currentContext || !hasPendingRefresh()) {
        return false;
      }

      var capturedToken = contextToken;
      var capturedChannelKey = currentChannelKey;
      if (!pendingRefreshBelongsTo(capturedToken, capturedChannelKey)) {
        clearPendingRefresh();
        return false;
      }

      if (currentRefreshRun) {
        if (
          currentRefreshRun.token === capturedToken &&
          currentRefreshRun.channelKey === capturedChannelKey
        ) {
          return false;
        }
        currentRefreshRun = null;
      }

      var batchHasMessage = pendingMessage;
      var capturedContext = copyContext(currentContext);
      var batch = {
        inquiryIds: Array.from(pendingInquiryIds),
        silent: !batchHasMessage,
        reason: batchHasMessage ? 'message' : 'subscribed',
        context: capturedContext
      };

      clearPendingRefresh();
      var run = {
        token: capturedToken,
        channelKey: capturedChannelKey,
        runId: ++refreshRunSequence,
        context: capturedContext,
        batch: batch,
        promise: null
      };
      currentRefreshRun = run;

      if (
        run.token !== contextToken ||
        run.channelKey !== currentChannelKey ||
        !currentContext ||
        currentRefreshRun !== run
      ) {
        settleRefresh(run);
        return false;
      }

      var refreshResult;
      try {
        refreshResult = onRefreshNeeded(batch);
      } catch (ignoredError) {
        settleRefresh(run);
        return true;
      }

      run.promise = Promise.resolve(refreshResult);
      run.promise.then(
        function () { settleRefresh(run); },
        function () { settleRefresh(run); }
      );
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
      if (!preparePendingRefresh(expectedToken, expectedChannelKey)) {
        return;
      }
      pendingSubscribed = true;
      scheduleFlush(expectedToken, expectedChannelKey);
    }

    function queueMessageRefresh(
      inquiryId,
      expectedToken,
      expectedChannelKey
    ) {
      if (!preparePendingRefresh(expectedToken, expectedChannelKey)) {
        return;
      }
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
        currentChannelUsable = true;
        currentChannelStatus = 'CONNECTING';

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

          if (TERMINAL_STATUSES[status]) {
            retireCurrentChannel(
              status,
              expectedToken,
              expectedChannelKey,
              nextChannel
            );
            return;
          }

          currentChannelUsable = true;
          currentChannelStatus = status;
          notifyStatus(status);
          if (status === 'SUBSCRIBED' && !subscribedRefreshQueued) {
            subscribedRefreshQueued = true;
            queueSubscribedRefresh(expectedToken, expectedChannelKey);
          }
        });
      } catch (ignoredError) {
        retireCurrentChannel(
          'CHANNEL_ERROR',
          expectedToken,
          expectedChannelKey,
          nextChannel
        );
      }
    }

    function sync(context) {
      var nextContext = normalizeContext(viewerKind, context);

      if (!nextContext) {
        contextToken += 1;
        resetContextWork();

        var invalidContextChannel = currentChannel;
        currentChannel = null;
        currentChannelUsable = false;
        currentChannelStatus = 'STOPPED';
        currentChannelKey = null;
        currentContext = null;
        safelyRemoveChannel(invalidContextChannel);
        notifyStatus('STOPPED');
        return false;
      }

      var nextChannelKey = makeChannelKey(viewerKind, nextContext);
      if (
        nextChannelKey === currentChannelKey &&
        currentChannel &&
        currentChannelUsable &&
        !TERMINAL_STATUSES[currentChannelStatus]
      ) {
        currentContext = nextContext;
        return true;
      }

      contextToken += 1;
      resetContextWork();

      var previousChannel = currentChannel;
      currentChannel = null;
      currentChannelUsable = false;
      currentChannelStatus = 'STOPPED';
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
      currentChannelUsable = false;
      currentChannelStatus = 'STOPPED';
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
