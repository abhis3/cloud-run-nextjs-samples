import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async () => {
  return {
    props: {
      page: 'guarded-ssg',
    },
  };
};

export default function GuardedSsgPage({ page }: { page: string }) {
  return (
    <main>
      <h1>{`Pages Router Guarded SSG (${page})`}</h1>
    </main>
  );
}
