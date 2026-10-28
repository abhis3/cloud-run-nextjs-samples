export const dynamic = 'force-dynamic';

export default async function ThrowAppPage() {
  throw new Error('App Router intentional 500');
}
