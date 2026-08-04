(function (root) {
  'use strict';

  if (!root || 'WoniyaPushSubscription' in root) {
    return;
  }

  var registrationInFlight = null;
  var activeRegistration = null;
  var deferredInstallPrompt = null;
  var installPromptInFlight = null;
  var installPromptConsumed = false;
  var appInstalled = false;
  var installStateListeners = new Set();

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

  function detectAndroid(navigatorObject) {
    var userAgent = navigatorObject && typeof navigatorObject.userAgent === 'string'
      ? navigatorObject.userAgent
      : '';

    return /Android/i.test(userAgent);
  }

  function detectIosSafari(navigatorObject, isIos) {
    if (!isIos || !navigatorObject) {
      return false;
    }

    var userAgent = typeof navigatorObject.userAgent === 'string'
      ? navigatorObject.userAgent
      : '';
    var isSafariFamily = /Safari/i.test(userAgent);
    var isOtherIosBrowser = /CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|GSA|YaBrowser|NAVER|Whale|FBAN|FBAV|Instagram|Line\//i.test(userAgent);

    return isSafariFamily && !isOtherIosBrowser;
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

  function getInstallStatus() {
    var navigatorObject = getNavigator();
    var isIos = detectIos(navigatorObject);
    var isStandalone = detectStandalone(navigatorObject);
    var installed = appInstalled || isStandalone;

    return {
      isAndroid: detectAndroid(navigatorObject),
      isIos: isIos,
      isIosSafari: detectIosSafari(navigatorObject, isIos),
      isStandalone: isStandalone,
      canPrompt: !installed && !installPromptConsumed && !!deferredInstallPrompt,
      installing: !!installPromptInFlight && !appInstalled,
      installed: installed
    };
  }

  function notifyInstallStatus() {
    Array.from(installStateListeners).forEach(function (listener) {
      try {
        listener(getInstallStatus());
      } catch (_error) {
        // A consumer callback must not interrupt helper state transitions.
      }
    });
  }

  function subscribeInstallStatus(listener) {
    if (typeof listener !== 'function') {
      return function () {};
    }

    installStateListeners.add(listener);
    try {
      listener(getInstallStatus());
    } catch (_error) {
      // A consumer callback must not interrupt subscription setup.
    }

    var subscribed = true;
    return function () {
      if (!subscribed) {
        return;
      }
      subscribed = false;
      installStateListeners.delete(listener);
    };
  }

  function promptInstall() {
    var installStatus = getInstallStatus();

    if (installStatus.installed) {
      return Promise.resolve({ ok: false, reason: 'already-installed' });
    }

    if (installPromptInFlight) {
      return installPromptInFlight;
    }

    if (!deferredInstallPrompt || installPromptConsumed) {
      return Promise.resolve({ ok: false, reason: 'unavailable' });
    }

    var promptEvent = deferredInstallPrompt;
    deferredInstallPrompt = null;
    installPromptConsumed = true;

    var executionPromise = Promise.resolve().then(function () {
      if (!promptEvent || typeof promptEvent.prompt !== 'function') {
        return { ok: false, reason: 'failed' };
      }

      return Promise.resolve(promptEvent.prompt()).then(function () {
        return Promise.resolve(promptEvent.userChoice);
      }).then(function (choice) {
        if (choice && choice.outcome === 'accepted') {
          return { ok: true, outcome: 'accepted' };
        }
        if (choice && choice.outcome === 'dismissed') {
          return { ok: false, reason: 'dismissed' };
        }
        return { ok: false, reason: 'failed' };
      });
    }).catch(function () {
      return { ok: false, reason: 'failed' };
    });

    var sharedPromise = executionPromise.then(function (result) {
      if (installPromptInFlight === sharedPromise) {
        installPromptInFlight = null;
        notifyInstallStatus();
      }
      return result;
    });

    installPromptInFlight = sharedPromise;
    notifyInstallStatus();
    return sharedPromise;
  }

  function handleBeforeInstallPrompt(event) {
    if (event && typeof event.preventDefault === 'function') {
      event.preventDefault();
    }

    if (
      detectStandalone(getNavigator()) ||
      appInstalled ||
      installPromptConsumed ||
      deferredInstallPrompt
    ) {
      return;
    }

    deferredInstallPrompt = event || null;
    if (deferredInstallPrompt) {
      notifyInstallStatus();
    }
  }

  function handleAppInstalled() {
    appInstalled = true;
    deferredInstallPrompt = null;
    installPromptConsumed = true;
    installPromptInFlight = null;
    notifyInstallStatus();
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

  if (typeof root.addEventListener === 'function') {
    root.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    root.addEventListener('appinstalled', handleAppInstalled);
  }

  root.WoniyaPushSubscription = Object.freeze({
    getSupportStatus: getSupportStatus,
    registerServiceWorker: registerServiceWorker,
    getRegistration: getRegistration,
    getNotificationPermission: getNotificationPermission,
    getInstallStatus: getInstallStatus,
    subscribeInstallStatus: subscribeInstallStatus,
    promptInstall: promptInstall
  });
})(typeof window !== 'undefined' ? window : this);
