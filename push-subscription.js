(function (root) {
  'use strict';

  if (!root || 'WoniyaPushSubscription' in root) {
    return;
  }

  var registrationInFlight = null;
  var activeRegistration = null;

  function getNavigator() {
    return root.navigator || null;
  }

  function detectIos(navigatorObject) {
    if (!navigatorObject) {
      return false;
    }

    var userAgent = typeof navigatorObject.userAgent === 'string'
      ? navigatorObject.userAgent
      : '';
    var platform = typeof navigatorObject.platform === 'string'
      ? navigatorObject.platform
      : '';
    var hasIosUserAgent = /iPad|iPhone|iPod/i.test(userAgent);
    var isDesktopModeIpad = platform === 'MacIntel' && Number(navigatorObject.maxTouchPoints) > 1;

    return hasIosUserAgent || isDesktopModeIpad;
  }

  function detectStandalone(navigatorObject) {
    var displayModeStandalone = false;

    if (typeof root.matchMedia === 'function') {
      try {
        displayModeStandalone = root.matchMedia('(display-mode: standalone)').matches === true;
      } catch (_error) {
        displayModeStandalone = false;
      }
    }

    return displayModeStandalone || !!(
      navigatorObject && navigatorObject.standalone === true
    );
  }

  function getSupportStatus() {
    var navigatorObject = getNavigator();
    var secureContext = root.isSecureContext === true;
    var serviceWorkerSupported = !!navigatorObject && 'serviceWorker' in navigatorObject;
    var notificationSupported = 'Notification' in root;
    var pushManagerSupported = 'PushManager' in root;
    var isIos = detectIos(navigatorObject);
    var isStandalone = detectStandalone(navigatorObject);

    return {
      secureContext: secureContext,
      serviceWorkerSupported: serviceWorkerSupported,
      notificationSupported: notificationSupported,
      pushManagerSupported: pushManagerSupported,
      supported: secureContext && serviceWorkerSupported && notificationSupported && pushManagerSupported,
      isIos: isIos,
      isStandalone: isStandalone,
      requiresIosHomeScreen: isIos && !isStandalone
    };
  }

  function getRegistration() {
    var status = getSupportStatus();
    var navigatorObject = getNavigator();

    if (!status.secureContext || !status.serviceWorkerSupported || !navigatorObject) {
      return Promise.resolve(null);
    }

    if (activeRegistration && activeRegistration.active) {
      return Promise.resolve(activeRegistration);
    }

    return navigatorObject.serviceWorker.getRegistration('/').then(function (registration) {
      if (registration) {
        activeRegistration = registration;
      }
      return registration || null;
    }).catch(function () {
      return null;
    });
  }

  function registerServiceWorker() {
    var status = getSupportStatus();
    var navigatorObject = getNavigator();

    if (!status.supported || !navigatorObject) {
      return Promise.resolve({ ok: false, reason: 'unsupported' });
    }

    if (status.requiresIosHomeScreen) {
      return Promise.resolve({ ok: false, reason: 'ios-home-screen-required' });
    }

    if (activeRegistration && activeRegistration.active) {
      return Promise.resolve({ ok: true, registration: activeRegistration });
    }

    if (registrationInFlight) {
      return registrationInFlight;
    }

    registrationInFlight = navigatorObject.serviceWorker
      .register('/service-worker.js', { scope: '/' })
      .then(function () {
        return navigatorObject.serviceWorker.ready;
      })
      .then(function (registration) {
        activeRegistration = registration;
        registrationInFlight = null;
        return { ok: true, registration: registration };
      })
      .catch(function () {
        registrationInFlight = null;
        return { ok: false, reason: 'registration-failed' };
      });

    return registrationInFlight;
  }

  function getNotificationPermission() {
    if (!('Notification' in root)) {
      return 'unsupported';
    }

    return root.Notification.permission;
  }

  root.WoniyaPushSubscription = Object.freeze({
    getSupportStatus: getSupportStatus,
    registerServiceWorker: registerServiceWorker,
    getRegistration: getRegistration,
    getNotificationPermission: getNotificationPermission
  });
})(typeof window !== 'undefined' ? window : this);
