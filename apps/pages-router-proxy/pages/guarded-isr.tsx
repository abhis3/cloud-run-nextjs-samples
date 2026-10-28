import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async () => {
  return {
    props: {
      page: 'guarded-isr',
    },
    revalidate: 60,
  };
};

export default function GuardedIsrPage({ page }: { page: string }) {
  return (
    <main>
      <h1>{`Pages Router Guarded ISR (${page})`}</h1>
    </main>
  );
}
