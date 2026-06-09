import { Platform } from 'react-native';
import { requireNativeModule } from 'expo-modules-core';

export type AppPermissionInfo = {
  packageName: string;
  appName: string;
  permissions: string[];
  suspicious: boolean;
};

export type CleanResult = {
  bytesFreed: number;
  message: string;
};

const Native = Platform.OS === 'android' ? requireNativeModule('SentinelAndroid') : null;

function unavailable<T>(fallback: T): Promise<T> {
  return Promise.resolve(fallback);
}

export async function requestCallScreeningRole(): Promise<boolean> {
  if (!Native) return false;
  return Native.requestCallScreeningRole();
}

export async function isCallBlockingEnabled(): Promise<boolean> {
  if (!Native) return false;
  return Native.getCallBlockingEnabled();
}

export async function getSpamNumbers(): Promise<string[]> {
  if (!Native) return [];
  return Native.getSpamNumbers();
}

export async function setSpamNumbers(numbers: string[]): Promise<void> {
  if (!Native) return;
  return Native.setSpamNumbers(numbers);
}

export async function auditAppPermissions(): Promise<AppPermissionInfo[]> {
  if (!Native) return [];
  return Native.auditAppPermissions();
}

export async function estimateJunkBytes(): Promise<number> {
  if (!Native) return 0;
  return Native.estimateJunkBytes();
}

export async function clearJunkFiles(): Promise<CleanResult> {
  if (!Native) {
    return unavailable({ bytesFreed: 0, message: 'Cleaner runs on Android only.' });
  }
  return Native.clearJunkFiles();
}
