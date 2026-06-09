import { useCallback, useEffect, useState } from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';

import {
  getSpamNumbers,
  isCallBlockingEnabled,
  requestCallScreeningRole,
  setSpamNumbers,
} from 'sentinel-android';

import { shared } from '@/constants/theme';

export default function CallsScreen() {
  const [enabled, setEnabled] = useState(false);
  const [status, setStatus] = useState('Checking call protection…');
  const [numbers, setNumbers] = useState('');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    if (Platform.OS !== 'android') {
      setStatus('Call blocking is available on Android only.');
      return;
    }
    const on = await isCallBlockingEnabled();
    setEnabled(on);
    const list = await getSpamNumbers();
    setNumbers(list.join('\n'));
    setStatus(
      on
        ? 'Spam call blocking is on. Add numbers below to block.'
        : 'Turn on call screening so we can block spam for you.'
    );
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function enableBlocking() {
    setBusy(true);
    try {
      const granted = await requestCallScreeningRole();
      if (granted) {
        setEnabled(true);
        setStatus('Spam call blocking is on.');
      } else {
        setStatus('Follow the system prompt to allow Sentinel Prime to screen calls.');
      }
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  async function saveNumbers() {
    setBusy(true);
    try {
      const list = numbers
        .split(/[\n,;]+/)
        .map((n) => n.trim())
        .filter(Boolean);
      await setSpamNumbers(list);
      setStatus(`Saved ${list.length} blocked number${list.length === 1 ? '' : 's'}.`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ScrollView style={shared.screen} contentContainerStyle={{ paddingBottom: 32 }}>
      <Text style={shared.title}>Spam Call Blocker</Text>
      <Text style={shared.subtitle}>We quietly block numbers you don't trust.</Text>

      <View style={shared.card}>
        <Text style={shared.status}>{status}</Text>
        {!enabled && Platform.OS === 'android' && (
          <Pressable style={shared.bigButton} disabled={busy} onPress={enableBlocking}>
            <Text style={shared.bigButtonText}>{busy ? 'Please wait…' : 'Turn On Protection'}</Text>
          </Pressable>
        )}
      </View>

      <View style={shared.card}>
        <Text style={{ color: '#f5f5f5', fontSize: 20, fontWeight: '600', marginBottom: 8 }}>
          Numbers to block
        </Text>
        <Text style={{ color: '#a3a3a3', fontSize: 18, marginBottom: 12 }}>
          One number per line. Example: 5551234567
        </Text>
        <TextInput
          style={{
            minHeight: 140,
            backgroundColor: '#141414',
            borderColor: '#333',
            borderWidth: 1,
            borderRadius: 12,
            padding: 16,
            color: '#f5f5f5',
            fontSize: 20,
            textAlignVertical: 'top',
          }}
          multiline
          value={numbers}
          onChangeText={setNumbers}
          placeholder="Enter phone numbers"
          placeholderTextColor="#666"
        />
        <Pressable style={shared.bigButton} disabled={busy} onPress={saveNumbers}>
          <Text style={shared.bigButtonText}>{busy ? 'Saving…' : 'Save Blocked Numbers'}</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}
