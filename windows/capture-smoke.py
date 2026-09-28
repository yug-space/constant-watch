"""Windows runner test using only a synthetic window, never personal screen data."""
import asyncio
import os
from pathlib import Path
import subprocess
import tempfile
import time
from constant_watch.windows_capture import capture

fixture = r'''
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Atlas capture verification'
$form.Width = 700; $form.Height = 350; $form.TopMost = $true
$form.StartPosition = 'CenterScreen'
$text = New-Object System.Windows.Forms.TextBox
$text.Multiline=$true; $text.Dock='Fill'; $text.Font=New-Object System.Drawing.Font('Arial',24)
$text.Text='Atlas review Friday at 10 AM'
$form.Controls.Add($text)
$form.Add_Shown({$form.Activate(); $text.Focus()})
[System.Windows.Forms.Application]::Run($form)
'''
async def check():
    with tempfile.TemporaryDirectory() as directory:
        script = Path(directory)/'fixture.ps1'; script.write_text(fixture, encoding='utf-8')
        p = subprocess.Popen(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(script)], creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            await asyncio.sleep(3)
            result = await capture()
            if result.get('skipped') == 'Windows desktop is locked or unavailable':
                raise RuntimeError('Runner has no interactive desktop; capture cannot be verified here')
            assert result.get('window_title') == 'Atlas capture verification', result
            assert 'Friday' in result['ax_text'], result
            assert 'Atlas' in result['ocr_text'], result
            excluded = await capture(excluded=[result['app_id']])
            assert excluded['skipped'] == 'Excluded application', excluded
            p.terminate(); p.wait(timeout=5)
            private_fixture = fixture.replace("$text.Multiline=$true", "$text.UseSystemPasswordChar=$true; $text.Multiline=$false")
            script.write_text(private_fixture, encoding='utf-8')
            p = subprocess.Popen(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(script)], creationflags=subprocess.CREATE_NO_WINDOW)
            await asyncio.sleep(3)
            private = await capture()
            assert private.get('skipped') == 'Secure text field is visible', private
            assert 'ax_text' not in private and 'ocr_text' not in private
            print('Synthetic Windows window: UI Automation + OCR + app exclusion + password-field protection passed.')
        finally:
            p.terminate(); p.wait(timeout=5)
asyncio.run(check())
