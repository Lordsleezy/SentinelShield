import { StyleSheet } from 'react-native';
import Colors from './Colors';

const c = Colors.dark;

export const theme = {
  colors: c,
  spacing: {
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  },
  font: {
    title: 32,
    heading: 24,
    body: 20,
    label: 18,
    button: 22,
  },
};

export const shared = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: c.background,
    padding: theme.spacing.lg,
  },
  title: {
    fontSize: theme.font.title,
    fontWeight: '700',
    color: c.text,
    marginBottom: theme.spacing.sm,
  },
  subtitle: {
    fontSize: theme.font.body,
    color: c.tabIconDefault,
    marginBottom: theme.spacing.lg,
    lineHeight: 28,
  },
  card: {
    backgroundColor: c.surface,
    borderRadius: 16,
    padding: theme.spacing.lg,
    marginBottom: theme.spacing.md,
    borderWidth: 1,
    borderColor: '#333',
  },
  bigButton: {
    backgroundColor: c.accent,
    minHeight: 64,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: theme.spacing.lg,
    marginTop: theme.spacing.md,
  },
  bigButtonText: {
    color: '#042f2e',
    fontSize: theme.font.button,
    fontWeight: '700',
  },
  secondaryButton: {
    backgroundColor: 'transparent',
    borderWidth: 2,
    borderColor: c.accent,
    minHeight: 56,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: theme.spacing.lg,
    marginTop: theme.spacing.md,
  },
  secondaryButtonText: {
    color: c.accent,
    fontSize: theme.font.label,
    fontWeight: '600',
  },
  status: {
    fontSize: theme.font.body,
    color: c.text,
    lineHeight: 28,
  },
  badgeDanger: {
    alignSelf: 'flex-start',
    backgroundColor: '#3b1212',
    borderColor: c.danger,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 4,
    marginTop: 8,
  },
  badgeDangerText: {
    color: '#fecaca',
    fontSize: 16,
    fontWeight: '600',
  },
});
