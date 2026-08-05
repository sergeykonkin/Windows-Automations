Option Explicit
Dim shell, args, cmd, i, arg

Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

If args.Count = 0 Then
    WScript.Echo "Usage: run-silent.vbs <program> [args...]"
    WScript.Quit 1
End If

cmd = ""
For i = 0 To args.Count - 1
    arg = args(i)
    If InStr(arg, " ") > 0 And Left(arg, 1) <> """" Then
        arg = """" & arg & """"
    End If
    If i > 0 Then cmd = cmd & " "
    cmd = cmd & arg
Next

shell.Run cmd, 0, False
