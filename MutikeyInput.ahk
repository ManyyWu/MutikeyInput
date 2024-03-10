#MaxHotkeysPerInterval 100
#HotkeyInterval 100
#NoEnv
#SingleInstance force
#MaxThreads 2
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer On
FileEncoding, UTF-8
SetStoreCapslockMode, Off
SetBatchLines, -1
SetKeyDelay -1
Process, Priority, , High

global g_output :=
global g_disableDebugMsg := false
global g_configFileName := "config.ini"
global g_leftKeys := "qwertasdfgzxcvb"
global g_rightKeys := "yuiophjkl;nm,./"
global g_PunctuationKeys := "[]{}:'""<>?-_=+\|`~"
global g_FuncKeys := { "Up": "{Up}", "Down": "{Down}", "Left": "{Left}", "Right": "{Right}", "PgUp": "{PgUp}", "PgDn": "{PgDn}", "Home": "{Home}", "End": "{End}" }
global KEY_TYPE := { "LEFT": 1, "RIGHT": 2, "FUNC": 3, "OTHER": 4 }
global TOOL_TIP_TYPE := { "STATER": 1, "DEBUG_MSG": 10 }

; 程序初始化
CApp.GetInstance().Init()

class Utils {
    class String {
        StrRev(str) {
            static rev := A_IsUnicode ? "_wcsrev" : "_strrev"
            DllCall("msvcrt.dll\" rev, "str", str, "cdecl")
            return str
        }
    }

    class Time {
        GetTimeMs() {
            return (a_hour * 3600 + a_min * 60 + a_sec) * 1000 + a_msec
        }
    }
}

class CToolTip {
    Show(text, which) {
        ToolTip, %text%, , , % which
    }

    ShowWithPos(text, which) {
        ToolTip, %text%, 0, 0, % which
    }
    
    DebugMsg(str, flush=true) {
        if (!g_disableDebugMsg) {
            if (!str and !g_output) {
                return
            }
            g_output .= str "`n"
            if (flush) {
                this.ShowWithPos(g_output, TOOL_TIP_TYPE.DEBUG_MSG)
            }
        }
    }

    FlushDebugMsg() {
        if (!g_disableDebugMsg) {
            this.ShowWithPos(g_output, TOOL_TIP_TYPE.DEBUG_MSG)
        }
    }

    ClearDebugMsg() {
        if (!g_disableDebugMsg) {
            g_output :=
            this.ShowWithPos(g_output, TOOL_TIP_TYPE.DEBUG_MSG)
        }
    }
}

class CMsgBox {
    Error(title, content) {
        CToolTip.FlushDebugMsg()
        MsgBox, , %title%, %content%
        ExitApp, 1
    }
}

class CStatusIndicator {
    static _inst :=

    __New(toolTipType) {
        if (IsObject(CStatusIndicator._inst)) {
            return CStatusIndicator._inst
        }
        CStatusIndicator.toolTipType := toolTipType
        CStatusIndicator.timer := ObjBindMethod(this, "OnToolTipTimeout")
        CStatusIndicator._inst := this
    }

    GetInstance() {
        if (IsObject(CStatusIndicator._inst)) {
            return CStatusIndicator._inst
        }
        CStatusIndicator._inst := new CStatusIndicator(TOOL_TIP_TYPE.STATER)
        return CStatusIndicator._inst
    }

    Show(duration) {
        if (this.GetIMEStat())
            text := "EN | "
        else
            text := "中 | "
        if (CKeyMappingManager.GetInstance().isPaused()) {
            text .= "单击"
        } else {
            text .= "并击"
        }
        CToolTip.Show("", this.toolTipType)
        CToolTip.Show(text, this.toolTipType)
        timer := this.timer
        SetTimer, % timer, % duration
    }

    GetIMEStat(WinTitle = "") {
        ifEqual, WinTitle, , SetEnv, WinTitle, A
        WinGet, hWnd, ID, %WinTitle%
        DefaultIMEWnd := DllCall("imm32\ImmGetDefaultIMEWnd", Uint, hWnd, Uint)
        DetectSave := A_DetectHiddenWindows
        DetectHiddenWindows, ON
        SendMessage, 0x283, 0x005, 0, , ahk_id %DefaultIMEWnd%
        DetectHiddenWindows, %DetectSave%
        return (1 = ErrorLevel) ; 1:ON 0:OFF
    }

    OnToolTipTimeout() {
        CToolTip.Show("", this.toolTipType)
        timer := this.timer
        SetTimer, % timer, Off
    }
}

class CConfigManager {
    static _inst :=
    config :=

    class CConfig {
        options :=
        mapping :=

        __New() {
            this.options := {}
            this.mapping := { "LeftKeyMapping": {}, "RightKeyMapping": {}, "FuncKeyMapping": {}, "PunctuationKeyMapping": {} }
        }
    }

    __New() {
        if (IsObject(CConfigManager._inst)) {
            return CConfigManager._inst
        }
        CConfigManager.config := new CConfigManager.CConfig()
        CConfigManager._inst := this
    }

    GetInstance() {
        if (IsObject(this._inst)) {
            return this._inst
        }
        this._inst := new CConfigManager()
        return this._inst
    }

    LoadConfig(configFileName) {
        ; 读取配置
        IniRead, statusIndicatorDuration, % configFileName, Options, StatusIndicatorDuration, 1000
        this.config.options.statusIndicatorDuration := statusIndicatorDuration
        IniRead, disableStatusIndicator, % configFileName, Options, DisableStatusIndicator, 0
        this.config.options.disableStatusIndicator := disableStatusIndicator
        IniRead, disableShiftSpace, % configFileName, Options, DisableShiftSpace, 1
        this.config.options.disableShiftSpace := disableShiftSpace
        IniRead, disableChAutoSpace, % configFileName, Options, DisableChAutoSpace, 0
        this.config.options.disableChAutoSpace := disableChAutoSpace
        IniRead, disableEnAutoSpace, % configFileName, Options, DisableEnAutoSpace, 1
        this.config.options.disableEnAutoSpace := disableEnAutoSpace

        ; 读取按键映射
        for part, mapping in this.config.mapping {
            IniRead, content, % configFileName, % part
            ; CToolTip.DebugMsg(part . ", Len:" . StrLen(content) . ", Content:`n" . content, false)

            idx := 0
            offset := 1
            while (idx := RegExMatch(content, "O)\s*([^`n]+)\s*=\s*([^`n]+)\s*`n*", obj, offset)) {
                ; CToolTip.DebugMsg(idx . ": " . obj.Value(1) . " = " . obj.Value(2), false)

                if ("FuncKeyMapping" = part and InStr(obj.Value(2), ";")) {
                    to := obj.Value(1)
                    StringLower, from, % obj.Value(2)
                    this.config.mapping[part][from] := to
                    this.config.mapping[part][Utils.String.StrRev(from)] := to
                } else {
                    StringLower, to, % StrReplace(obj.Value(1), "!") ; !用来防止解析失败
                    StringLower, from, % obj.Value(2)
                    this.config.mapping[part][from] := to
                    this.config.mapping[part][Utils.String.StrRev(from)] := to
                }
                offset += obj.Len()
            }
        }
        
        ; CToolTip.DebugMsg("StatusIndicatorDuration=" . this.config.options.statusIndicatorDuration, false)
        ; CToolTip.DebugMsg("DisableStatusIndicator=" . this.config.options.disableStatusIndicator, false)
        ; CToolTip.DebugMsg("DisableShiftSpace=" . this.config.options.disableShiftSpace, false)
        ; CToolTip.DebugMsg("DisableChAutoSpace=" . this.config.options.disableChAutoSpace, false)
        ; CToolTip.DebugMsg("DisableEnAutoSpace=" . this.config.options.disableEnAutoSpace, false)
    }

    SaveConfig(filename) {
    }

    GetConfig() {
        return this.config
    }
    
    GetStatusIndicatorDuration() {
        return this.config.options.statusIndicatorDuration
    }
}

class CKeyMappingManager {
    static _inst :=
    keyPartition := {}
    config := {}
    pressedKeys := {}
    IsReleasedOnce := true
    paused := false

    __New() {
        if (IsObject(CKeyMappingManager._inst)) {
            return CKeyMappingManager._inst
        }
        CKeyMappingManager._inst := this
    }

    GetInstance() {
        if (IsObject(this._inst)) {
            return this._inst
        }
        this._inst := new CKeyMappingManager()
        return this._inst
    }

    Pause(flag) {
        this.paused := flag
        this.pressedKeys := {}
        if (!flag) {
            this.registerReWriteKeys()
        } else {
            this.unRregisterReWriteKeys()
        }
    }
    
    isPaused() {
        return this.paused
    }

    Init(config) {
        this.config := config
        this.InitPartition()
        this.RegisterKeyMapping()
    }

    InitPartition() {
        for _, k in StrSplit(g_leftKeys) {
            this.keyPartition[k] := KEY_TYPE.LEFT
        }
        for _, k in StrSplit(g_rightKeys) {
            this.keyPartition[k] := KEY_TYPE.RIGHT
        }
        for k, _ in g_FuncKeys {
            this.keyPartition[k] := KEY_TYPE.FUNC
        }
        for _, k in StrSplit(g_PunctuationKeys) {
            this.keyPartition[k] := KEY_TYPE.OTHER
        }
    }

    VerifyKeyMapping() {
        for part, mapping in this.config.mapping {
            for keys, value in mapping {
                from := StrSplit(keys)
                to := StrSplit(value)
                if ("FuncKeyMapping" = part and (";" = from[1] or ";" = from[2])) {
                    ; TODO: map<keyName>
                } else {
                    if (1 != to.Length() or from.Length() > 2 or from.Length() < 1) {
                        Gosub l_ErrorInvalidKeyMapping
                    }
                    if (!this.IsLeftKey(to[1]) and !this.IsRightKey(to[1]) and !this.IsOtherKey(to[1])) {
                    CMsgBox.Error("Error", "[" . A_ScriptName . ":" . A_LineNumber . "]Unsupported key mapping: " . value . "=" . keys)
                        Gosub l_ErrorInvalidKeyMapping
                    }
                    if (!this.IsLeftKey(from[1]) and !this.IsRightKey(from[1]) and "+" != from[1]) { ; +表示Shift
                    CMsgBox.Error("Error", "[" . A_ScriptName . ":" . A_LineNumber . "]Unsupported key mapping: " . value . "=" . keys)
                        Gosub l_ErrorInvalidKeyMapping
                    }
                    if (2 = from.Length() and !this.IsLeftKey(from[2]) and !this.IsRightKey(from[2]) and "+" != from[2]) {
                    CMsgBox.Error("Error", "[" . A_ScriptName . ":" . A_LineNumber . "]Unsupported key mapping: " . value . "=" . keys)
                        Gosub l_ErrorInvalidKeyMapping
                    }
                    if (2 = from.Length() and from[1] = from[2]) {
                        Gosub l_ErrorInvalidKeyMapping
                    }
                }
                Continue

                l_ErrorInvalidKeyMapping:
                    CMsgBox.Error("Error", "[" . A_ScriptName . ":" . A_LineNumber . "]Unsupported key mapping: " . value . "=" . keys)
                    return
            }
        }
        
        ; for part, mapping in CConfigManager.config.mapping {
        ;     for from, to in mapping {
        ;         CToolTip.DebugMsg(part . "." from . " = " . to, false)
        ;     }
        ; }
    }

    RegisterKeyMapping() {
        this.VerifyKeyMapping()
        this.registerReWriteKeys()

        ; 清除调试信息
        onClearDebugMsg := ObjBindMethod(CApp.GetInstance(), "OnClearDebugMsg")
        Hotkey, ~^c Up, % onClearDebugMsg

        ; 指示器
        onLeftClick := ObjBindMethod(CApp.GetInstance(), "OnLeftClick")
        Hotkey, ~LButton Up, % onLeftClick
        onUpdateStatusIndicator := ObjBindMethod(CApp.GetInstance(), "onUpdateStatusIndicator")
        Hotkey, ~#Space Up, % onUpdateStatusIndicator
        Hotkey, ~^Space Up, % onUpdateStatusIndicator
        
        ; 退出
        onExit := ObjBindMethod(CApp.GetInstance(), "OnExit")
        HotKey, !F1 Up, % onExit

        ; 暂停
        onPause := ObjBindMethod(CApp.GetInstance(), "OnPause")
        HotKey, RShift Up, % onPause

        ; 重载
        onReload := ObjBindMethod(CApp.GetInstance(), "onReload")
        HotKey, !F2 Up, % onReload
    
        ; 屏蔽<Shift + Space> <Alt + Shift> 
        HotKey, !Shift Up, l_disabledHotKey
        HotKey, +Alt Up, l_disabledHotKey
        HotKey, +Space Up, l_disabledHotKey

        l_disabledHotKey:
            return
    }

    registerReWriteKeys() {
        setReWriteKeys := {}
        for part, mapping in this.config.mapping {
            for keys, _ in mapping {
                for _, key in StrSplit(keys) {
                    setReWriteKeys[key] := true
                }
            }
        }

        onKeyDown := ObjBindMethod(this, "OnKeyDown")
        onKeyUp := ObjBindMethod(this, "OnKeyUp")
        for key in setReWriteKeys {
            ; CToolTip.DebugMsg("key: " . key, false)
    
            Hotkey, $%key%, % onKeyDown, On
            Hotkey, $+%key%, % onKeyDown, On
            Hotkey, ~$*%key% Up, % onKeyUp, On
        }
        Hotkey, $Space, % onKeyDown, On
        Hotkey, ~$*Space Up, % onKeyUp, On
    }

    unRregisterReWriteKeys() {
        setReWriteKeys := {}
        for part, mapping in this.config.mapping {
            for keys, _ in mapping {
                for _, key in StrSplit(keys) {
                    setReWriteKeys[key] := true
                }
            }
        }

        onKeyDown := ObjBindMethod(this, "OnKeyDown")
        onKeyUp := ObjBindMethod(this, "OnKeyUp")
        for key in setReWriteKeys {
            ; CToolTip.DebugMsg("key: " . key, false)
    
            Hotkey, $%key%, % onKeyDown, Off
            Hotkey, $+%key%, % onKeyDown, Off
            Hotkey, ~$*%key% Up, % onKeyUp, Off
        }
        Hotkey, $Space, % onKeyDown, Off
        Hotkey, ~$*Space Up, % onKeyUp, Off
    }

    IsLeftKey(key) {
        return (KEY_TYPE.LEFT = this.keyPartition[key])
    }

    IsRightKey(key) {
        return (KEY_TYPE.RIGHT = this.keyPartition[key])
    }

    IsFuncKey(key) {
        return (KEY_TYPE.FUNC = this.keyPartition[key])
    }

    IsOtherKey(key) {
        return (KEY_TYPE.OTHER = this.keyPartition[key])
    }

    OnKeyDown() {
        if (this.paused) {
            return
        }
        ; CToolTip.DebugMsg("KeyDown: " . A_thisHotkey, false)

        ; 1. 格式: "$+k" 或 "$k" 或 "$+Space" 或 "$Space"
        ; 2. 按着不松会重复触发OnKeyDown
        ; 3. 多线程环境同时按下/释放按键时有bug, 会在OnKeyDown触发通配符: "~$*k" 或 "~$*k Up", 不要开启多线程
        isRepeated := false
        len := StrLen(A_thisHotkey)
        for i, k in StrSplit(A_thisHotkey, , "$~* ") {
            if (len > 3) {
                if (InStr(A_thisHotkey, "Space")) {
                    if (this.pressedKeys[" "]) {
                        isRepeated := true
                    }
                    this.pressedKeys[" "] := true
                    Break
                }
                CMsgBox.Error("Fatal", "[" . A_ScriptName . ":" . A_LineNumber . "]Unreachable, A_thisHotkey: " . A_thisHotkey)
                return
            } else {
                if (this.pressedKeys[k]) {
                    isRepeated := true
                    Continue
                }
                this.pressedKeys[k] := true
            }
        }
        if (!isRepeated) {
            this.IsReleasedOnce := false
        }
    }

    OnKeyUp() {
        if (this.paused) {
            return
        }
        ; CToolTip.DebugMsg("OnKeyUp: " . A_thisHotkey, false)

        if (!this.IsReleasedOnce) {
            this.IsReleasedOnce := true

            pressedCount := 0
            isShiftPressed := false
            isSpacePressed := false
            leftKeys := ""
            rightKeys := ""
            leftOutKey := ""
            rightOutKey := ""
            extKeys := ""
            for k, _ in this.pressedKeys {
                pressedCount++

                if ("+" = k) {
                    isShiftPressed := true
                } else if (" " = k) {
                    isSpacePressed := true
                } else if (this.IsLeftKey(k)) {
                    leftKeys .= k
                } else if (this.IsRightKey(k)) {
                    rightKeys .= k
                } else {
                    CMsgBox.Error("Fatal", "[" . A_ScriptName . ":" . A_LineNumber . "]Unreachable, A_thisHotkey: " . A_thisHotkey)
                    return
                }
            }
            ; CToolTip.DebugMsg("Left: " . leftKeys . ", Right: " . rightKeys . ", Shift: " . isShiftPressed . ", Space: " . isSpacePressed, false)

            ; 只按了右手按键
            leftLen := StrLen(leftKeys)
            rightLen := StrLen(rightKeys)
            isOnlyRight := false
            isFuncKey := false
            if (0 = leftLen and rightLen > 0) {
                isOnlyRight := true
                if (this.pressedKeys[";"]) {
                    isFuncKey := true
                }
            }

            if (leftLen > 0) {
                leftOutKey := this.config.mapping.LeftKeyMapping[leftKeys]
                ; CToolTip.DebugMsg("out: " leftOutKey, false)
            }

            if (rightLen > 0 and !isOnlyRight) {
                rightOutKey := this.config.mapping.RightKeyMapping[rightKeys]
                ; CToolTip.DebugMsg("out: " rightOutKey, false)
            }

            if (isFuncKey) {
                rightOutKey := g_FuncKeys[this.config.mapping.FuncKeyMapping[rightKeys]]
            } else if (isOnlyRight) {
                shiftSymbal := ""
                if (isShiftPressed) {
                    shiftSymbal := "+"
                }
                rightOutKey := this.config.mapping.PunctuationKeyMapping[shiftSymbal . rightKeys]
            }

            if (isShiftPressed and !isOnlyRight) {
                StringUpper, leftOutKey, % leftOutKey
                StringUpper, rightOutKey, % rightOutKey
            }

            if (isSpacePressed and !isFuncKey) {
                extKeys .= " "
            }

            ; CToolTip.DebugMsg("send: " . leftOutKey . rightOutKey . extKeys)
            if (isFuncKey) {
                SendEvent % rightOutKey
            } else {
                SendRaw %leftOutKey%%rightOutKey%%extKeys%
            }
        }

        ; 1. 格式: "~$*k Up" 或 "~$*Space Up"
        ; 2. 按键释放时清除
        ; 3. 同时释放时只会触发一次OnKeyUp
        newPressedKeys := {}
        for k, _ in this.pressedKeys {
            ; CToolTip.DebugMsg(k . ", State: " GetKeyState(k, "P"), false)
            keyName := k
            if(" " = keyName) {
                keyName := "Space"
            }
            if (!GetKeyState(keyName, "P")) { ; 不加P获取不到准确状态
                ; CToolTip.DebugMsg("Clear: " keyName, false)
                Continue
            }
            newPressedKeys[k] := true
        }
        this.pressedKeys := newPressedKeys

        tmpPressedKeys := ""
        for k, _ in this.pressedKeys {
            tmpPressedKeys .= k
        }
        ; CToolTip.DebugMsg("tmp: " . tmpPressedKeys, false)
    }
}

class CApp {
    static _inst :=

    __New() {
        if (IsObject(CApp._inst)) {
            return CApp._inst
        }
        CApp._inst := this
    }

    GetInstance() {
        if (IsObject(this._inst)) {
            return this._inst
        }
        this._inst := new CApp()
        return this._inst
    }

    Init() {
        ; ToolTip指定坐标时相对于屏幕
        CoordMode, ToolTip, Screen
        ; 初始化配置
        CConfigManager.GetInstance().LoadConfig(g_configFileName)
        ; 初始化按键映射
        CKeyMappingManager.GetInstance().Init(CConfigManager.GetInstance().GetConfig())
        ; 初始化定时器
        this.InitTimer()

        CToolTip.FlushDebugMsg()
    }

    InitTimer() {
        if (!g_disableDebugMsg) {
            onTick4DebugMsg := ObjBindMethod(this, "OnTick4DebugMsg")
            SetTimer, % onTick4DebugMsg, 10000
        }
    }

    OnUpdateStatusIndicator() {
        CStatusIndicator.GetInstance().Show(CConfigManager.GetInstance().GetStatusIndicatorDuration())
    }

    OnLeftClick() {
        If ("IBeam" = A_Cursor) {
            isEditMode := 1
        } else if("Arrow" = A_Cursor) {
            isEditMode := 0
        }
        ControlGetFocus, theFocus
        if (InStr(theFocus, "Edit") or ("Scintilla1" = theFocus) or ("DirectUIHWND1" = theFocus) or (1 = isEditMode)) {
            this.OnUpdateStatusIndicator()
        }
    }

    OnPause() {
        CKeyMappingManager.GetInstance().Pause(!CKeyMappingManager.GetInstance().isPaused())
        this.OnUpdateStatusIndicator()
    }

    OnReload() {
        Reload
    }

    OnExit() {
        ExitApp
    }

    OnClearDebugMsg() {
        CToolTip.ClearDebugMsg()
    }

    OnTick4DebugMsg() {
        CToolTip.FlushDebugMsg()
    }
}
; 要求:
;     1. 微软输入法需要先打开兼容性，否则获取不到输入法状态
;
; 并击:
;     左单 => 左手按键
;     左双 => 右手按钮
;     左单 + 右单 => 左手按键 + 左手按键
;     左单 + 右双 => 左手按键 + 右手按键
;     左双 + 右单 => 右手按键 + 左手按键
;     左双 + 右双 => 右手按键 + 右手按键
;     LShift => Shift
;     RShift => 切换模式
;
; 单击:
;     右单 => 符号:
;         u => [
;         i => ]
;         j => ;
;         k => '
;         n => ,
;         m => .
;         , => /
;
;         y => -
;         h => +
;         o => |
;         p => ~
;         
;     右双 => 功能键:
;         ; + hjkl => 方向键
;         ; + ui => PgDown/PgUp
;         ; + nm => End/Home

; TODO: 左边大写/右边大写/左右大写，连按右边
; 连续输入方案：用buff缓存所有按下的按键，抬键时上屏，不足以上屏的先缓存。缺点容错率低？