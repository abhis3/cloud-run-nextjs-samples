import React from 'react';
import Image from 'next/image';
import traced from '../public/traced.json';

export default function HomePage() {
  return (
    <main>
      <h1>Home Page</h1>
      <p data-testid="traced">{JSON.stringify(traced)}</p>
      <Image src="/logo.png" alt="Logo" width={32} height={32} />
    </main>
  );
}
