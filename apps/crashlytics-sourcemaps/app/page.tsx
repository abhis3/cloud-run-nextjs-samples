import React from 'react';
import { ClientCrashWidget } from './client-widget';

export default function HomePage() {
  return (
    <main>
      <h1>Crashlytics Source Maps Sample</h1>
      <ClientCrashWidget />
    </main>
  );
}
