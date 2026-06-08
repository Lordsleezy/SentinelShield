rule EICAR_Test_File {
    meta:
        description = "Harmless test pattern used to verify the scanner works"
        severity = "high"
    strings:
        $eicar = "EICAR-STANDARD-ANTIVIRUS-TEST-FILE" nocase
    condition:
        $eicar
}

rule Double_Extension {
    meta:
        description = "File may be hiding its true type with a double extension"
        severity = "medium"
    condition:
        filename matches /\.(pdf|doc|jpg|png|txt)\.(exe|scr)$/ nocase
}

rule Encoded_PowerShell {
    meta:
        description = "Heavily encoded PowerShell often used by harmful software"
        severity = "high"
    strings:
        $enc = "-EncodedCommand" nocase
        $b64 = "FromBase64String" nocase
    condition:
        all of them
}

rule WScript_Launcher {
    meta:
        description = "Script launcher that may run commands without your knowledge"
        severity = "medium"
    strings:
        $wscript = "WScript.Shell" nocase
        $cscript = "CScript" nocase
    condition:
        all of them
}

rule Hidden_Window_Execution {
    meta:
        description = "Command may run in a hidden window"
        severity = "medium"
    strings:
        $hidden = "-WindowStyle Hidden" nocase
    condition:
        $hidden
}

rule Ransomware_Extension {
    meta:
        description = "File extension often used by ransomware"
        severity = "high"
    condition:
        filename matches /\.(locked|encrypted|crypted)$/ nocase
}

rule Keylogger_API {
    meta:
        description = "Patterns associated with keylogging software"
        severity = "high"
    strings:
        $async = "GetAsyncKeyState" nocase
        $hook = "SetWindowsHookEx" nocase
    condition:
        any of them
}

rule Remote_Access {
    meta:
        description = "Patterns associated with remote access tools"
        severity = "high"
    strings:
        $rev = "reverse_shell" nocase
        $bind = "bind_shell" nocase
    condition:
        any of them
}

rule Crypto_Miner {
    meta:
        description = "Patterns associated with cryptocurrency mining"
        severity = "medium"
    strings:
        $stratum = "stratum+tcp" nocase
        $xmrig = "xmrig" nocase
        $monero = "monero" nocase
    condition:
        any of them
}
