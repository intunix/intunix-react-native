export const calls: [string, unknown[]][] = [];
const record = (name: string) => (...args: unknown[]) => { calls.push([name, args]); };
export const NativeModules = {
  Intunix: Object.fromEntries(
    ['initialize', 'identify', 'reset', 'track', 'screen', 'setContext', 'showForm', 'register', 'unregister', 'setTheme'].map((n) => [n, record(n)]),
  ),
};
export const Platform = { OS: 'ios', select: (o: Record<string, unknown>) => o.ios ?? o.default };
export const requireNativeComponent = () => () => null;
export type ViewProps = Record<string, unknown>;
export type NativeSyntheticEvent<T> = { nativeEvent: T };
