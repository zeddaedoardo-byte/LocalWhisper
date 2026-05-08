using System.Runtime.InteropServices;
using LocalWhisper.Windows.Interop;
using LocalWhisper.Windows.Models;

namespace LocalWhisper.Windows.Services;

public sealed class PushToTalkService : IDisposable
{
    private readonly object _stateLock = new();
    private readonly HashSet<int> _pressedKeys = [];
    private readonly NativeMethods.HookProc _hookProc;
    private nint _hookHandle;
    private SynchronizationContext? _callbackContext;
    private Action? _onPress;
    private Action? _onRelease;
    private Action? _onEscape;
    private Action? _onLockToggle;
    private bool _isTriggerPressed;
    private bool _isLockPressed;
    private PushToTalkTrigger _trigger = PushToTalkTrigger.LeftControl;
    private PushToTalkTrigger? _lockTrigger;

    public PushToTalkService()
    {
        _hookProc = HookCallback;
    }

    public bool IsActive => _hookHandle != nint.Zero;

    public void SetTrigger(PushToTalkTrigger trigger)
    {
        lock (_stateLock)
        {
            _trigger = trigger;
            _isTriggerPressed = false;
            _isLockPressed = false;
            _pressedKeys.Clear();
        }
    }

    /// <summary>
    /// Sets the optional secondary "lock-in" hotkey. Pass null to disable.
    /// The lock state machine fires <c>onLockToggle</c> only on the
    /// transition to pressed; releases of the combo are ignored (toggle
    /// semantics).
    /// </summary>
    public void SetLockTrigger(PushToTalkTrigger? trigger)
    {
        lock (_stateLock)
        {
            _lockTrigger = trigger;
            _isLockPressed = false;
        }
    }

    public void Start(Action onPress, Action onRelease, Action? onEscape = null, Action? onLockToggle = null)
    {
        Stop();
        _onPress = onPress;
        _onRelease = onRelease;
        _onEscape = onEscape;
        _onLockToggle = onLockToggle;
        _callbackContext = SynchronizationContext.Current;

        var moduleHandle = NativeMethods.CurrentModuleHandle();
        _hookHandle = NativeMethods.SetWindowsHookEx(
            NativeMethods.WhKeyboardLl,
            _hookProc,
            moduleHandle,
            0);

        if (_hookHandle == nint.Zero)
        {
            var error = Marshal.GetLastWin32Error();
            throw new InvalidOperationException($"Could not install the global keyboard hook (Win32 error {error}).");
        }
    }

    public void Stop()
    {
        if (_hookHandle != nint.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookHandle);
            _hookHandle = nint.Zero;
        }

        lock (_stateLock)
        {
            _isTriggerPressed = false;
            _isLockPressed = false;
            _pressedKeys.Clear();
        }
    }

    public void Dispose()
    {
        Stop();
    }

    private nint HookCallback(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0)
        {
            var message = wParam.ToInt32();
            var isDown = message is NativeMethods.WmKeyDown or NativeMethods.WmSysKeyDown;
            var isUp = message is NativeMethods.WmKeyUp or NativeMethods.WmSysKeyUp;

            if (isDown || isUp)
            {
                var data = Marshal.PtrToStructure<NativeMethods.KeyboardLowLevelHookStruct>(lParam);
                var normalizedKey = NativeMethods.NormalizeModifierKey((int)data.VkCode, (int)data.ScanCode);
                if (normalizedKey == 0x1B && isDown)
                {
                    PostTransition(_onEscape);
                }
                HandleKeyEvent(normalizedKey, isDown);
            }
        }

        return NativeMethods.CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    private void HandleKeyEvent(int virtualKey, bool isDown)
    {
        Action? transition = null;
        Action? lockTransition = null;

        lock (_stateLock)
        {
            if (isDown)
            {
                _pressedKeys.Add(virtualKey);
            }
            else
            {
                _pressedKeys.Remove(virtualKey);
            }

            var isPressed = IsTriggerCurrentlyPressed(_trigger);
            if (isPressed != _isTriggerPressed)
            {
                _isTriggerPressed = isPressed;
                transition = isPressed ? _onPress : _onRelease;
            }

            if (_lockTrigger is not null && _lockTrigger.Id != _trigger.Id)
            {
                var lockPressed = IsTriggerCurrentlyPressed(_lockTrigger);
                if (lockPressed != _isLockPressed)
                {
                    _isLockPressed = lockPressed;
                    // Toggle on press only — release of the lock combo is meaningless.
                    if (lockPressed)
                    {
                        lockTransition = _onLockToggle;
                    }
                }
            }
        }

        PostTransition(transition);
        PostTransition(lockTransition);
    }

    private void PostTransition(Action? transition)
    {
        if (transition is null)
        {
            return;
        }

        if (_callbackContext is not null)
        {
            _callbackContext.Post(_ => transition(), null);
        }
        else
        {
            transition();
        }
    }

    private bool IsTriggerCurrentlyPressed(PushToTalkTrigger trigger)
    {
        foreach (var requiredKey in trigger.RequiredVirtualKeys)
        {
            if (!IsKeyDown(requiredKey))
            {
                return false;
            }
        }

        return true;
    }

    private bool IsKeyDown(int virtualKey)
    {
        if (_pressedKeys.Contains(virtualKey))
        {
            return true;
        }

        return NativeMethods.IsVirtualKeyDown(virtualKey);
    }
}
