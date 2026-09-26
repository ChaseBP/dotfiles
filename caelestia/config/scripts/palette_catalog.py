"""Descriptions and explicit actions for Caelestia's stock bindings.

Keys are resolved from variables plus user overrides and checked against live
bindings. Unknown runtime bindings remain reference-only; never invoke Lua IDs.
"""


def flatten(value):
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, list):
        return [key for item in value for key in flatten(item)]
    return []


def stock_actions(v):
    rows = []

    def add(var, label, group, expr=None, *, code=None, keys=None, confirm=False, keywords=""):
        rows.append(dict(id=var, label=label, group=group,
                         keys=flatten(v.get(var, []) if keys is None else keys),
                         lua=code or ("hl.dispatch(" + expr + ")" if expr else None),
                         confirm=confirm, keywords=keywords))

    for var, label, name in [
        ('kbLauncher', 'Open application launcher', 'launcher'),
        ('kbSession', 'Open session and power menu', 'session'),
        ('kbShowSidebar', 'Show sidebar', 'sidebar'),
        ('kbClearNotifs', 'Clear notifications', 'clearNotifs'),
        ('kbShowPanels', 'Show all Caelestia panels', 'showall'),
        ('kbLock', 'Lock screen', 'lock'),
    ]:
        add(var, label, 'Desktop', f'hl.dsp.global("caelestia:{name}")', confirm=var == 'kbClearNotifs')
    add('kbRestoreLock', 'Restart shell and restore lock screen', 'System', code='hl.dispatch(hl.dsp.exec_cmd("caelestia shell -d")); hl.dispatch(hl.dsp.global("caelestia:lock"))', confirm=True)
    add('kbSleep', 'Suspend computer', 'System', 'hl.dsp.exec_cmd(v.sleepGestureCmd)', confirm=True)
    for name, label, command in [('restartShell', 'Restart Caelestia shell', 'qs -c caelestia kill; sleep .1; caelestia shell -d'), ('killShell', 'Stop Caelestia shell', 'qs -c caelestia kill')]:
        add(name, label, 'System', f'hl.dsp.exec_cmd("{command}")', keys=['CTRL + SUPER + ALT + R' if name == 'restartShell' else 'CTRL + SUPER + SHIFT + R'], confirm=True)

    for var, label, field in [('kbTerminal','Open terminal','terminal'),('kbBrowser','Open browser','browser'),('kbEditor','Open editor','editor'),('kbFileExplorer','Open file manager','fileExplorer'),('kbAudioSettings','Open audio settings','audioSettings')]:
        add(var, label, 'Apps', f'hl.dsp.exec_cmd(v.{field})')
    for var, label, ws in [('kbSpecialWs','Show or hide scratchpad','specialws'),('kbSystemMonitorWs','Show system monitor','sysmon'),('kbCommunicationWs','Show communication apps','communication'),('kbMusicWs','Show music apps','music'),('kbTodoWs','Show task apps','todo')]:
        add(var, label, 'Desktop', code=f'fn.toggle("{ws}")()')

    for var, label, expr in [
        ('kbWindowCycleNext','Cycle to next window','hl.dsp.window.cycle_next()'),
        ('kbWindowCyclePrev','Cycle to previous window','hl.dsp.window.cycle_next({next=false})'),
        ('kbWindowGroupCycleNext','Next window in group','hl.dsp.group.next()'),
        ('kbWindowGroupCyclePrev','Previous window in group','hl.dsp.group.prev()'),
        ('kbToggleGroup','Toggle window group','hl.dsp.group.toggle()'),
        ('kbUngroup','Remove window from group','hl.dsp.window.move({out_of_group=true})'),
        ('kbGroupLockActive','Toggle active group lock','hl.dsp.group.lock_active()'),
        ('kbCenterWindow','Center floating window','hl.dsp.window.center()'),
        ('kbPinWindow','Pin or unpin floating window','hl.dsp.window.pin()'),
        ('kbWindowFullscreen','Toggle fullscreen','hl.dsp.window.fullscreen({mode="fullscreen"})'),
        ('kbWindowBorderedFullscreen','Toggle maximized window','hl.dsp.window.fullscreen({mode="maximized"})'),
        ('kbToggleWindowFloating','Toggle floating window','hl.dsp.window.float()'),
        ('kbCloseWindow','Close focused window','hl.dsp.window.close()'),
    ]:
        add(var, label, 'Windows', expr, confirm=var == 'kbCloseWindow')
    for direction in ('left','right','up','down'):
        add('focus'+direction, 'Focus window '+direction, 'Windows', f'hl.dsp.focus({{direction="{direction}"}})', keys=['SUPER + '+direction])
        add('move'+direction, 'Move window '+direction, 'Windows', f'hl.dsp.window.move({{direction="{direction}"}})', keys=['SUPER + SHIFT + '+direction])
    for var, label, x, y in [('kbWindowDecreaseWidth','Decrease window width',-10,0),('kbWindowIncreaseWidth','Increase window width',10,0),('kbWindowDecreaseHeight','Decrease window height',0,-10),('kbWindowIncreaseHeight','Increase window height',0,10)]:
        add(var, label, 'Windows', code=f'fn.resize_active_window({x},{y})()')
    add('kbNormalizeWindow', 'Normalize window size and center', 'Windows', code='hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55,70))); hl.dispatch(hl.dsp.window.center())')
    add('kbWindowPip', 'Put window in picture-in-picture', 'Windows', code='local a=hl.get_active_window(); if a then local p=fn.move_actions(a) or {}; if not a.floating then table.insert(p,1,hl.dsp.window.float()) end; table.insert(p,hl.dsp.window.pin({action="on",window="address:"..a.address})); for _,d in ipairs(p) do hl.dispatch(d) end end', keywords='pip video corner')
    add('kbMoveWindow', 'Drag window — hold shortcut and left-drag', 'Mouse', keys=flatten(v.get('kbMoveWindow'))+['SUPER + mouse:272'])
    add('kbResizeWindow', 'Resize window — hold shortcut and drag', 'Mouse', keys=flatten(v.get('kbResizeWindow'))+['SUPER + mouse:273'])

    for var, label, method, ws in [
        ('kbPrevWs','Previous workspace','focus','-1'),('kbNextWs','Next workspace','focus','+1'),
        ('kbPrevWsGroup','Previous workspace group','focus','-10'),('kbNextWsGroup','Next workspace group','focus','+10'),
        ('kbMoveWinToWsNext','Send window to next workspace','window.move','+1'),('kbMoveWinToWsPrev','Send window to previous workspace','window.move','-1'),
        ('kbMoveWinToWsSpecial','Send window to scratchpad','window.move','special:special'),('kbMoveWinFromWsSpecial','Bring window out of scratchpad','window.move','e+0'),
    ]:
        add(var, label, 'Workspaces', f'hl.dsp.{method}({{workspace="{ws}"}})')
    for var, label, action, group in [('kbGoToWs','Go to workspace','focus',''),('kbMoveWinToWs','Send window to workspace','move',''),('kbGoToWsGroup','Go to workspace group','focus','group'),('kbMoveWinToWsGroup','Send window to workspace group','move','group')]:
        base=v.get(var)
        if isinstance(base,str) and base.strip():
            for i in range(1,11):
                add(var+str(i),f'{label} {i}', 'Workspaces', code=f'fn.wsaction("{action}","{group}",{i})()', keys=[base+' + '+str(i%10)])

    for var, label, expr in [
        ('kbScreenshot','Capture screenshot','hl.dsp.exec_cmd("caelestia screenshot")'),
        ('kbScreenshotFreeze','Capture region with frozen screen','hl.dsp.global("caelestia:screenshotFreeze")'),
        ('kbScreenshotRegion','Capture screen region','hl.dsp.global("caelestia:screenshot")'),
        ('kbRecord','Start or stop screen recording','hl.dsp.exec_cmd("caelestia record")'),
        ('kbRecordSound','Record screen with sound','hl.dsp.exec_cmd("caelestia record -s")'),
        ('kbRecordRegion','Record screen region','hl.dsp.exec_cmd("caelestia record -r")'),
        ('kbColorPicker','Pick and copy a screen color','hl.dsp.exec_cmd("hyprpicker -a")'),
        ('kbClipboard','Open clipboard history','hl.dsp.exec_cmd("caelestia clipboard")'),
        ('kbClipboardDel','Delete clipboard history entries','hl.dsp.exec_cmd("caelestia clipboard -d")'),
        ('kbEmoji','Choose an emoji','hl.dsp.exec_cmd("caelestia emoji -p")'),
    ]:
        add(var,label,'Capture' if var.startswith(('kbScreenshot','kbRecord','kbColor')) else 'Clipboard',expr, keywords='snip image capture' if var.startswith('kbScreenshot') else '')
    add('kbClipboardPasteLatest','Type latest history entry — use shortcut in destination','Clipboard', keywords='paste typing')
    for var,label,name,hardware in [('kbMediaToggle','Play or pause media','mediaToggle',['XF86AudioPlay','XF86AudioPause']),('kbMediaNext','Next media track','mediaNext',['XF86AudioNext']),('kbMediaPrev','Previous media track','mediaPrev',['XF86AudioPrev']),('kbMediaStop','Stop media','mediaStop',['XF86AudioStop'])]:
        add(var,label,'Media',f'hl.dsp.global("caelestia:{name}")',keys=flatten(v.get(var))+hardware)
    for key,label,name in [('XF86MonBrightnessUp','Increase brightness','brightnessUp'),('XF86MonBrightnessDown','Decrease brightness','brightnessDown')]:
        add(key,label,'Media',f'hl.dsp.global("caelestia:{name}")',keys=[key])
    add('kbVolumeMute','Mute or unmute speakers','Media','hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")',keys=flatten(v.get('kbVolumeMute'))+['XF86AudioMute'])
    add('micMute','Mute or unmute microphone','Media','hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")',keys=['XF86AudioMicMute'])
    add('volumeUp','Increase volume','Media','hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l "..(v.volumeMax/100).." @DEFAULT_AUDIO_SINK@ "..v.volumeStep.."%+")',keys=['XF86AudioRaiseVolume'])
    add('volumeDown','Decrease volume','Media','hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ "..v.volumeStep.."%-")',keys=['XF86AudioLowerVolume'])
    add('wallpaper','Choose wallpaper','Desktop','hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/wall")',keys=['SUPER + SHIFT + W'])
    add('wallpaperRandom','Choose random wallpaper','Desktop','hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/wall random")',keys=['SUPER + ALT + W'])
    add('osk','Show or hide on-screen keyboard','Desktop','hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/osk toggle")',keys=['SUPER + SHIFT + K'],keywords='tablet touch typing')
    for on in ('on','off'):
        add('tablet'+on, 'Tablet mode '+on+' — automatic hinge switch', 'Hardware',keys=['switch:'+on+':Intel Virtual Switches'])
    add('testNotification','Send test notification — diagnostic shortcut','System',keys=['SUPER + ALT + F12'])
    return rows
