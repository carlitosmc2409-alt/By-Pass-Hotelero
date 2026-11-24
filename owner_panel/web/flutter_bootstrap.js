{{flutter_js}}
{{flutter_build_config}}

// Limpia cualquier Service Worker antiguo que pueda servir una versión en caché
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function(registrations) {
    for (let registration of registrations) {
      registration.unregister();
    }
  });
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
