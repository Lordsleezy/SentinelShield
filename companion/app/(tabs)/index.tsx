import { Link } from 'expo-router';
import { ScrollView, Text, View } from 'react-native';

import { shared } from '@/constants/theme';

const links = [
  { href: '/calls' as const, title: 'Block spam calls', desc: 'Stop unwanted callers automatically.' },
  { href: '/permissions' as const, title: 'Check app permissions', desc: 'See which apps use your camera, mic, or location.' },
  { href: '/cleaner' as const, title: 'Clean up junk', desc: 'Free space by clearing temporary files.' },
];

export default function HomeScreen() {
  return (
    <ScrollView style={shared.screen} contentContainerStyle={{ paddingBottom: 32 }}>
      <Text style={shared.title}>Sentinel Prime</Text>
      <Text style={shared.subtitle}>Simple phone protection for everyone.</Text>

      {links.map((item) => (
        <Link key={item.href} href={item.href} asChild>
          <View style={shared.card}>
            <Text style={{ color: '#14b8a6', fontSize: 24, fontWeight: '700', marginBottom: 8 }}>
              {item.title}
            </Text>
            <Text style={shared.status}>{item.desc}</Text>
            <Text style={{ color: '#14b8a6', fontSize: 18, marginTop: 12, fontWeight: '600' }}>Open →</Text>
          </View>
        </Link>
      ))}
    </ScrollView>
  );
}
