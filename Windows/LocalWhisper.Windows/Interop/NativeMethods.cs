using System.Diagnostics;
using System.Runtime.InteropServices;

namespace LocalWhisper.Windows.Interop;

internal static class NativeMethods
{
    internal const int WhKeyboardLl = 13;
    internal const int WmKeyDown = 0x0100;
    internal const int WmKeyUp = 0x0101;
    internal const int WmSysKeyDown = 0x0104;
    internal const int WmSysKeyUp = 0x0105;
    internal const int MapvkVscToVkEx = 0x03;
    internal const int VkControl = 0x11;
    internal const int VkShift = 0x10;
    internal const int VkMenu = 0x12;
    internal const int VkV = 0x56;
    internal const int InputKeyboard = 1;
    internal const uint KeyEventFKeyUp = 0x0002;
    internal const uint KeyEventFScancode = 0x0008;

    internal static readonly int InputSize = Marshal.SizeOf<Input>();

    internal delegate nint HookProc(int nCode, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct KeyboardLowLevelHookStruct
    {
        public uint VkCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public nint DwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Input
    {
        public int Type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct InputUnion
    {
        [FieldOffset(0)]
        public KeyboardInput Ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct KeyboardInput
    {
        public ushort WVk;
        public ushort WScan;
        public uint DwFlags;
        public uint Time;
        public nint DwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern nint SetWindowsHookEx(int idHook, HookProc lpfn, nint hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(nint hhk);

    [DllImport("user32.dll")]
    internal static extern nint CallNextHookEx(nint hhk, int nCode, nint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    internal static extern nint GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll")]
    internal static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("user32.dll")]
    internal static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

    // --- Job Object support: ensures child processes (whisper-server) die
    //     with the parent even on hard crash / TaskKill. ---

    internal const int JobObjectExtendedLimitInformation = 9;
    internal const uint JobObjectLimitKillOnJobClose = 0x2000;

    [StructLayout(LayoutKind.Sequential)]
    internal struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public nuint MinimumWorkingSetSize;
        public nuint MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public nuint Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct JobObjectExtendedLimitInformationStruct
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public nuint ProcessMemoryLimit;
        public nuint JobMemoryLimit;
        public nuint PeakProcessMemoryUsed;
        public nuint PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint CreateJobObject(nint lpJobAttributes, string? lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetInformationJobObject(
        nint hJob,
        int infoClass,
        nint lpJobObjectInfo,
        uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AssignProcessToJobObject(nint hJob, nint hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(nint hObject);

    internal static nint CurrentModuleHandle()
    {
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        return GetModuleHandle(module?.ModuleName);
    }

    internal static int NormalizeModifierKey(int vkCode, int scanCode)
    {
        if (vkCode is not (VkControl or VkShift or VkMenu))
        {
            return vkCode;
        }

        var mapped = (int)MapVirtualKey((uint)scanCode, MapvkVscToVkEx);
        return mapped == 0 ? vkCode : mapped;
    }

    internal static bool IsVirtualKeyDown(int virtualKey) =>
        (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    internal static Input[] BuildCtrlVInputs() =>
    [
        KeyboardInput(VkControl, keyUp: false),
        KeyboardInput(VkV, keyUp: false),
        KeyboardInput(VkV, keyUp: true),
        KeyboardInput(VkControl, keyUp: true)
    ];

    private static Input KeyboardInput(int virtualKey, bool keyUp) => new()
    {
        Type = InputKeyboard,
        U = new InputUnion
        {
            Ki = new KeyboardInput
            {
                WVk = (ushort)virtualKey,
                WScan = 0,
                DwFlags = keyUp ? KeyEventFKeyUp : 0,
                Time = 0,
                DwExtraInfo = nint.Zero
            }
        }
    };
}
