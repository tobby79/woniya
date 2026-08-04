'use strict';

var UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
var AUDIENCE_CONFIG = {
  parent: {
    title: '문의에 새 메시지가 도착했어요',
    body: '원이야에서 확인해 주세요.',
    pathname: '/parent.html'
  },
  staff: {
    title: '학부모 문의가 도착했어요',
    body: '원이야에서 내용을 확인해 주세요.',
    pathname: '/class-admin.html'
  }
};

function isPlainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function normalizeNotificationData(value) {
  if (!isPlainObject(value) || !Object.prototype.hasOwnProperty.call(AUDIENCE_CONFIG, value.audience)) {
    return null;
  }

  if (!isValidUuid(value.classId) || !isValidUuid(value.inquiryId) || !isValidUuid(value.eventId)) {
    return null;
  }

  return {
    audience: value.audience,
    classId: value.classId,
    inquiryId: value.inquiryId,
    eventId: value.eventId
  };
}

function buildTargetUrl(data) {
  var config = AUDIENCE_CONFIG[data.audience];
  var target = new URL(config.pathname, self.location.origin);
  target.searchParams.set('class_id', data.classId);
  target.searchParams.set('view', 'inquiry');
  target.searchParams.set('inquiry_id', data.inquiryId);
  return target;
}

self.addEventListener('install', function (event) {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function (event) {
  if (!event.data) {
    return;
  }

  var payload;
  try {
    payload = event.data.json();
  } catch (_error) {
    return;
  }

  var data = normalizeNotificationData(payload);
  if (!data) {
    return;
  }

  var config = AUDIENCE_CONFIG[data.audience];
  event.waitUntil(self.registration.showNotification(config.title, {
    body: config.body,
    icon: '/assets/pwa/icon-192.png',
    tag: 'woniya-inquiry-' + data.audience + '-' + data.inquiryId,
    renotify: true,
    requireInteraction: false,
    silent: false,
    data: data
  }));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();

  var data = normalizeNotificationData(event.notification.data);
  if (!data) {
    return;
  }

  var target = buildTargetUrl(data);
  event.waitUntil(
    self.clients.matchAll({
      includeUncontrolled: true,
      type: 'window'
    }).then(function (clientList) {
      for (var index = 0; index < clientList.length; index += 1) {
        var client = clientList[index];
        var clientUrl;

        try {
          clientUrl = new URL(client.url);
        } catch (_error) {
          continue;
        }

        if (
          clientUrl.origin === self.location.origin &&
          clientUrl.pathname === target.pathname &&
          clientUrl.search === target.search &&
          typeof client.focus === 'function'
        ) {
          return client.focus();
        }
      }

      if (typeof self.clients.openWindow === 'function') {
        return self.clients.openWindow(target.pathname + target.search);
      }

      return undefined;
    })
  );
});
