'use client';

export default function ErrorBoundary({
  error,
}: {
  error: Error & { digest?: string };
}) {
  return <div>App Router Error Boundary: {error.message || 'Server Error'}</div>;
}
