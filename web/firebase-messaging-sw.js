importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBIH2x45D1Cc5KO4uQxdYEJnBdW2_g1tR0',
  appId: '1:1038536143668:web:b203ecc9de3f475a14eb61',
  messagingSenderId: '1038536143668',
  projectId: 'social-960eb',
  authDomain: 'social-960eb.firebaseapp.com',
  storageBucket: 'social-960eb.firebasestorage.app',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message:', payload);
  
  const notificationTitle = payload.notification?.title || 'New Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
