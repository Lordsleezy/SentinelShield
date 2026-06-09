import { SymbolView } from 'expo-symbols';
import { Tabs } from 'expo-router';

import Colors from '@/constants/Colors';

const tint = Colors.dark.tint;

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: tint,
        tabBarInactiveTintColor: Colors.dark.tabIconDefault,
        tabBarStyle: {
          backgroundColor: Colors.dark.surface,
          borderTopColor: '#333',
          height: 72,
          paddingBottom: 8,
        },
        tabBarLabelStyle: {
          fontSize: 14,
          fontWeight: '600',
        },
        headerStyle: {
          backgroundColor: Colors.dark.background,
        },
        headerTintColor: Colors.dark.text,
        headerTitleStyle: {
          fontSize: 22,
          fontWeight: '700',
        },
      }}>
      <Tabs.Screen
        name="index"
        options={{
          title: 'Home',
          tabBarIcon: ({ color }) => (
            <SymbolView name={{ ios: 'shield', android: 'shield', web: 'shield' }} tintColor={color} size={28} />
          ),
        }}
      />
      <Tabs.Screen
        name="calls"
        options={{
          title: 'Calls',
          tabBarIcon: ({ color }) => (
            <SymbolView name={{ ios: 'phone', android: 'call', web: 'call' }} tintColor={color} size={28} />
          ),
        }}
      />
      <Tabs.Screen
        name="permissions"
        options={{
          title: 'Apps',
          tabBarIcon: ({ color }) => (
            <SymbolView name={{ ios: 'lock.shield', android: 'security', web: 'security' }} tintColor={color} size={28} />
          ),
        }}
      />
      <Tabs.Screen
        name="cleaner"
        options={{
          title: 'Cleaner',
          tabBarIcon: ({ color }) => (
            <SymbolView name={{ ios: 'trash', android: 'delete', web: 'delete' }} tintColor={color} size={28} />
          ),
        }}
      />
    </Tabs>
  );
}
