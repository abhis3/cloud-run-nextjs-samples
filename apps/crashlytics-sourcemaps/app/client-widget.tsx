'use client';

import React, { useState } from 'react';

export function ClientCrashWidget() {
  const [count, setCount] = useState(0);
  return (
    <section>
      <p>{`Client Widget Ready (clicks: ${count})`}</p>
      <button type="button" onClick={() => setCount((c) => c + 1)}>
        Increment
      </button>
    </section>
  );
}
