import { useCallback, useEffect, useState } from 'react';
import { Platform, Pressable, Text, View } from 'react-native';

import { clearJunkFiles, estimateJunkBytes } from 'sentinel-android';

import { shared } from '@/constants/theme';

function formatMb(bytes: number): string {
  return (bytes / (1024 * 1024)).toFixed(1);
}

export default function CleanerScreen() {
  const [junkBytes, setJunkBytes] = useState(0);
  const [status, setStatus] = useState('Checking for junk files…');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    if (Platform.OS !== 'android') {
      setStatus('Cleaner runs on Android only.');
      return;
    }
    const bytes = await estimateJunkBytes();
    setJunkBytes(bytes);
    setStatus(
      bytes > 1024 * 1024
        ? `About ${formatMb(bytes)} MB of temporary files can be cleared.`
        : 'Your phone looks tidy already.'
    );
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function runClean() {
    setBusy(true);
    try {
      const result = await clearJunkFiles();
      setStatus(result.message);
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={shared.screen}>
      <Text style={shared.title}>Cleaner</Text>
      <Text style={shared.subtitle}>Clear temporary files to free up space.</Text>

      <View style={shared.card}>
        <Text style={shared.status}>{status}</Text>
        {junkBytes > 0 && (
          <Text style={{ color: '#14b8a6', fontSize: 28, fontWeight: '700', marginTop: 12 }}>
            {formatMb(junkBytes)} MB
          </Text>
        )}
      </View>

      <Pressable style={shared.bigButton} disabled={busy} onPress={runClean}>
        <Text style={shared.bigButtonText}>{busy ? 'Cleaning…' : 'Clean Now'}</Text>
      </Pressable>
    </View>
  );
}
