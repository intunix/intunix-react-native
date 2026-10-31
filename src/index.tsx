import { useState, type ComponentType } from 'react';
import { NativeModules, Platform, requireNativeComponent, type ViewProps, type NativeSyntheticEvent } from 'react-native';

/** Options for {@link Intunix.initialize}. Names follow the web and native SDKs. */
export interface IntunixOptions {
  /** API origin. Leave as is unless Intunix gave you another host. */
  apiHost?: string;
  /** Forms (ids or slugs) whose triggers should be live. Auto-activate forms are live anyway. */
  register?: string[];
  /** Load the whole SDK-enabled catalog instead of only `register`. */
  registerAll?: boolean;
  flushIntervalMs?: number;
  maxQueueSize?: number;
  /** Wait before a screen-triggered form shows. */
  screenTriggerDelayMs?: number;
  /** Keep tracked events on the device (they still fire event triggers). */
  disableEventApi?: boolean;
  /** Native SDK logs (Logcat / Xcode console). */
  debug?: boolean;
}

export type JsonValue = string | number | boolean | null | JsonValue[] | { [k: string]: JsonValue };
export type Properties = Record<string, JsonValue>;

const LINKING_ERROR =
  `@intunix/react-native is not linked. ${Platform.select({ ios: "Run 'pod install' in ios/. ", default: '' })}` +
  'Rebuild the app after installing the package (Expo Go is not supported; use a development build).';

const Native: {
  initialize(apiKey: string, options: IntunixOptions): void;
  identify(userId: string, traits: Properties): void;
  reset(): void;
  track(event: string, properties: Properties): void;
  screen(name: string): void;
  setContext(context: Properties | null): void;
  showForm(form: string, context: Properties | null): void;
  register(form: string): void;
  unregister(form: string): void;
} = NativeModules.Intunix ?? new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

/** Intunix feedback forms. Call `initialize` once, at app start. */
export const Intunix = {
  version: '1.5.7',
  initialize: (apiKey: string, options: IntunixOptions = {}) => Native.initialize(apiKey, options),
  /** Identify the signed-in user. Call on every login. */
  identify: (userId: string, traits: Properties = {}) => Native.identify(userId, traits),
  /** Call on logout: forgets the user, rotates the anonymous id and ends the session. */
  reset: () => Native.reset(),
  track: (event: string, properties: Properties = {}) => Native.track(event, properties),
  /** Tell Intunix which screen is showing. Drives "App screen" triggers and screen targeting. */
  screen: (name: string) => Native.screen(name),
  /** Merge values into the session context sent with responses; null clears it. */
  setContext: (context: Properties | null) => Native.setContext(context),
  clearContext: () => Native.setContext(null),
  /** Show a form now (still subject to its cadence and targeting). Accepts the form id or slug. */
  showForm: (idOrSlug: string, context?: Properties) => Native.showForm(idOrSlug, context ?? null),
  /** Make a form's triggers live. */
  register: (idOrSlug: string) => Native.register(idOrSlug),
  unregister: (idOrSlug: string) => Native.unregister(idOrSlug),
};

interface NativeFormProps extends ViewProps {
  form: string;
  formContext?: Properties | null;
  onHeightChange?: (e: NativeSyntheticEvent<{ height: number }>) => void;
  onFinished?: (e: NativeSyntheticEvent<Record<string, never>>) => void;
}

let NativeForm: ComponentType<NativeFormProps> | null = null;
const nativeForm = () => (NativeForm ??= requireNativeComponent<NativeFormProps>('IntunixFormView'));

export interface IntunixFormProps extends ViewProps {
  /** Form id or slug. */
  form: string;
  /** Values sent with the response, on top of `Intunix.setContext`. */
  context?: Properties;
  /** Called once the visitor submits or closes the form. */
  onFinished?: () => void;
}

/**
 * A form placed in your own layout (the web SDK's inline form). Takes the form's height,
 * draws nothing until it loads, and collapses once the visitor is done.
 */
export function IntunixForm({ form, context, onFinished, style, ...rest }: IntunixFormProps) {
  // A native view needs a non-zero size before it can measure its content.
  const [height, setHeight] = useState(1);
  const View = nativeForm();
  return (
    <View
      {...rest}
      form={form}
      formContext={context ?? null}
      style={[style, { height }]}
      onHeightChange={(e: NativeSyntheticEvent<{ height: number }>) => setHeight(Math.max(1, e.nativeEvent.height))}
      onFinished={() => onFinished?.()}
    />
  );
}

export default Intunix;
