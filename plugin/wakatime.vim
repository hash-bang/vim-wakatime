" ============================================================================
" File:        wakatime.vim
" Description: Automatic time tracking for Vim.
" Maintainer:  WakaTime <support@wakatime.com>
" License:     BSD, see LICENSE.txt for more details.
" Website:     https://wakatime.com/
" ============================================================================

let s:VERSION = '4.0.0'


" Init {{{

    " Check Vim version
    if v:version < 700
        echoerr "This plugin requires vim >= 7."
        finish
    endif

    " Only load plugin once
    if exists("g:loaded_wakatime")
        finish
    endif
    let g:loaded_wakatime = 1

    " Backup & Override cpoptions
    let s:old_cpo = &cpo
    set cpo&vim

    " Globals
    let s:plugin_directory = expand("<sfile>:p:h") . '/'
    let s:config_file = expand("$HOME/.wakatime.cfg")
    let s:config_file_already_setup = 0

    " For backwards compatibility, rename wakatime.conf to wakatime.cfg
    if !filereadable(s:config_file)
        if filereadable(expand("$HOME/.wakatime"))
            exec "silent !mv" expand("$HOME/.wakatime") expand("$HOME/.wakatime.conf")
        endif
        if filereadable(expand("$HOME/.wakatime.conf"))
            if !filereadable(s:config_file)
                let contents = ['[settings]'] + readfile(expand("$HOME/.wakatime.conf"), '')
                call writefile(contents, s:config_file)
                call delete(expand("$HOME/.wakatime.conf"))
            endif
        endif
    endif

    " Set default python binary location
    if !exists("g:wakatime_PythonBinary")
        let g:wakatime_PythonBinary = 'python'
    endif

    " Set default heartbeat frequency in minutes
    if !exists("g:wakatime_HeartbeatFrequency")
        let g:wakatime_HeartbeatFrequency = 2
    endif

" }}}


" Function Definitions {{{

    function! s:StripWhitespace(str)
        return substitute(a:str, '^\s*\(.\{-}\)\s*$', '\1', '')
    endfunction
    
    function! s:SetupConfigFile()
        if !s:config_file_already_setup

            " Create config file if does not exist
            if !filereadable(s:config_file)
                let key = input("[WakaTime] Enter your wakatime.com api key: ")
                if key != ''
                    call writefile(['[settings]', 'debug = false', printf("api_key = %s", key), 'hidefilenames = false', 'ignore =', '    COMMIT_EDITMSG$', '    PULLREQ_EDITMSG$', '    MERGE_MSG$', '    TAG_EDITMSG$'], s:config_file)
                    echo "[WakaTime] Setup complete! Visit http://wakatime.com to view your logged time."
                endif

            " Make sure config file has api_key
            else
                let found_api_key = 0
                let lines = readfile(s:config_file)
                for line in lines
                    let group = split(line, '=')
                    if len(group) == 2 && s:StripWhitespace(group[0]) == 'api_key' && s:StripWhitespace(group[1]) != ''
                        let found_api_key = 1
                    endif
                endfor
                if !found_api_key
                    let key = input("[WakaTime] Enter your wakatime.com api key: ")
                    let lines = lines + [join(['api_key', key], '=')]
                    call writefile(lines, s:config_file)
                    echo "[WakaTime] Setup complete! Visit http://wakatime.com to view your logged time."
                endif
            endif

            let s:config_file_already_setup = 1
        endif
    endfunction

    function! s:GetCurrentFile()
        return expand("%:p")
    endfunction

    function! s:Api(targetFile, time, is_write, last)
        let targetFile = a:targetFile
        if targetFile == ''
            let targetFile = a:last[2]
        endif
        if targetFile != ''
            let python_bin = g:wakatime_PythonBinary
            if has('win32') || has('win64')
                if python_bin == 'python'
                    let python_bin = 'pythonw'
                endif
            endif
            let cmd = [python_bin, '-W', 'ignore', '"' . s:plugin_directory . 'packages/wakatime/cli.py"']
            let cmd = cmd + ['--file', shellescape(targetFile)]
            let cmd = cmd + ['--plugin', shellescape(printf('vim/%d vim-wakatime/%s', v:version, s:VERSION))]
            if a:is_write
                let cmd = cmd + ['--write']
            endif
            "let cmd = cmd + ['--verbose']
            if has('win32') || has('win64')
                exec 'silent !start /min cmd /c "' . join(cmd, ' ') . '"'
            else
                exec 'silent !' . join(cmd, ' ') . ' &'
            endif
            call s:SetLastHeartbeat(a:time, a:time, targetFile)
        endif
    endfunction
    
    function! s:GetLastHeartbeat()
        if !filereadable(expand("$HOME/.wakatime.data"))
            return [0, 0, '']
        endif
        let last = readfile(expand("$HOME/.wakatime.data"), '', 3)
        if len(last) != 3
            return [0, 0, '']
        endif
        return last
    endfunction
    
    function! s:SetLastHeartbeat(time, last_update, targetFile)
        call writefile([substitute(printf('%d', a:time), ',', '.', ''), substitute(printf('%d', a:last_update), ',', '.', ''), a:targetFile], expand("$HOME/.wakatime.data"))
    endfunction

    function! s:EnoughTimePassed(now, last)
        let prev = a:last[0]
        if a:now - prev > g:wakatime_HeartbeatFrequency * 60
            return 1
        endif
        return 0
    endfunction
    
" }}}


" Event Handlers {{{

    function! s:handleActivity(is_write)
        call s:SetupConfigFile()
        let targetFile = s:GetCurrentFile()
        let now = localtime()
        let last = s:GetLastHeartbeat()
        if targetFile !~ "-MiniBufExplorer-" && targetFile !~ "--NO NAME--" && targetFile != ""
            if a:is_write || s:EnoughTimePassed(now, last) || targetFile != last[2]
                call s:Api(targetFile, now, a:is_write, last)
            endif
        endif
    endfunction

" }}}


" Autocommand Events {{{

    augroup Wakatime
        autocmd!
        autocmd BufEnter * call s:handleActivity(0)
        autocmd VimEnter * call s:handleActivity(0)
        autocmd BufWritePost * call s:handleActivity(1)
        autocmd CursorMoved,CursorMovedI * call s:handleActivity(0)
    augroup END

" }}}


" Restore cpoptions
let &cpo = s:old_cpo
