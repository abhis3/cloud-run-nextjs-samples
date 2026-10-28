import React from 'react';

export async function getServerSideProps() {
  throw new Error('Pages Router intentional 500');
}

export default function ThrowPages() {
  return <div>Unreachable Pages Router 500</div>;
}
