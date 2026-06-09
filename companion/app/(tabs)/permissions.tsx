import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Platform, Pressable, ScrollView, Text, View } from 'react-native';

import { auditAppPermissions, type AppPermissionInfo } from 'sentinel-android';

import { shared } from '@/constants/theme';

export default function PermissionsScreen() {
  const [apps, setApps] = useState<AppPermissionInfo[]>([]);
  const [status, setStatus] = useState('Tap the button to scan your apps.');
  const [busy, setBusy] = useState(false);

  const runAudit = useCallback(async () => {
    if (Platform.OS !== 'android') {
      setStatus('App permission audit runs on Android only.');
      return;
    }
    setBusy(true);
    setStatus('Scanning installed apps…');
    try {
      const results = await auditAppPermissions();
      setApps(results);
      const suspicious = results.filter((a) => a.suspicious).length;
      setStatus(
        suspicious > 0
          ? `Found ${suspicious} app${suspicious === 1 ? '' : 's'} with unusual access.`
          : "No suspicious apps found. You're all clear."
      );
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void runAudit();
  }, [runAudit]);

  return (
    <ScrollView style={shared.screen} contentContainerStyle={{ paddingBottom: 32 }}>
      <Text style={shared.title}>App Permissions</Text>
      <Text style={shared.subtitle}>We flag apps that use camera, mic, and location together.</Text>

      <Pressable style={shared.bigButton} disabled={busy} onPress={runAudit}>
        <Text style={shared.bigButtonText}>{busy ? 'Scanning…' : 'Scan My Apps'}</Text>
      </Pressable>

      <Text style={[shared.status, { marginTop: 20 }]}>{status}</Text>

      {busy && <ActivityIndicator color="#14b8a6" style={{ marginTop: 16 }} />}

      {apps.map((app) => (
        <View key={app.packageName} style={shared.card}>
          <Text style={{ color: '#f5f5f5', fontSize: 22, fontWeight: '700' }}>{app.appName}</Text>
          <Text style={{ color: '#a3a3a3', fontSize: 16, marginTop: 4 }}>{app.packageName}</Text>
          <Text style={{ color: '#ccfbf1', fontSize: 18, marginTop: 10 }}>
            Uses: {app.permissions.join(', ')}
          </Text>
          {app.suspicious && (
            <View style={shared.badgeDanger}>
              <Text style={shared.badgeDangerText}>Needs a closer look</Text>
            </View>
          )}
        </View>
      ))}
    </ScrollView>
  );
}
