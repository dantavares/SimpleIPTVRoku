' ********** MainScene.brs – original + simple search on InstantReplay **********

sub init()
    m.top.backgroundURI = "pkg:/images/L_background-controls.jpg"

    m.save_feed_url = m.top.FindNode("save_feed_url")  ' Save url to registry

    m.get_channel_list = m.top.FindNode("get_channel_list") ' get url from registry and parse the feed
    m.get_channel_list.ObserveField("content", "SetContent") ' when content is parsed, display list

    m.list = m.top.FindNode("list")
    m.list.ObserveField("itemSelected", "setChannel")

    m.video = m.top.FindNode("Video")
    m.video.ObserveField("state", "checkState")

    ' Store the full, unfiltered channel list for search
    m.fullContent = invalid
    m.searchTerm  = ""

    content = createObject("RoSGNode", "ContentNode")
    content.title = "Bem Vindo"
    content.streamformat = "mp4"
    content.url = "https://abre.ai/canaldocliente7mp4"
    m.video.content = content
    m.video.control = "play"

    m.get_channel_list.control = "RUN"

    'm.top.backgroundURI = "pkg:/images/background-controls.jpg"
end sub

' **************************************************************

function onKeyEvent(key as String, press as Boolean) as Boolean
    result = false

    if press then
        ' Simple layout control as in original
        if key = "right" then
            m.list.SetFocus(false)
            m.top.SetFocus(true)
            m.video.translation = [0, 0]
            m.video.width = 0
            m.video.height = 0
            result = true

        else if key = "left" then
            m.list.SetFocus(true)
            m.video.translation = [800, 100]
            m.video.width = 960
            m.video.height = 540
            result = true

        else if key = "back" then
            m.list.SetFocus(true)
            m.video.translation = [800, 100]
            m.video.width = 960
            m.video.height = 540
            m.video.control = "stop"
            result = true

        else if key = "options" then
            ' * button: edit playlist URL (unchanged)
            showdialog()
            result = true
        else if key = "Play/Pause" then
            m.video.control = "stop"
            result = true

        else if key = "InstantReplay" or key = "replay" then
            ' Counterclockwise arrow button: open search box
            showSearchDialog()
            result = true
        end if
    end if

    return result
end function

sub checkState()
    state = m.video.state
    if state = "error" then
        m.top.dialog = CreateObject("roSGNode", "Dialog")
        m.top.dialog.title = "Error: " + str(m.video.errorCode)
        m.top.dialog.message = m.video.errorMsg
    end if
end sub

' Called when get_channel_list finishes parsing the feed
sub SetContent()
    ' Save the full content once so we can always search against it
    m.fullContent = m.get_channel_list.content

    ' Show the full list by default
    m.list.content = m.fullContent
    m.list.SetFocus(true)
    m.top.backgroundURI = "pkg:/images/background-controls.jpg"
end sub

sub setChannel()
    if m.list.content = invalid then return

    ' Handle simple flat list and (optionally) sectioned lists
    if m.list.content.getChild(0).getChild(0) = invalid then
        content = m.list.content.getChild(m.list.itemSelected)
    else
        itemSelected = m.list.itemSelected
        for i = 0 to m.list.currFocusSection - 1
            itemSelected = itemSelected - m.list.content.getChild(i).getChildCount()
        end for
        content = m.list.content.getChild(m.list.currFocusSection).getChild(itemSelected)
    end if

    if content = invalid then return

    ' Set supported formats
    content.streamFormat = "hls, mp4, mkv, mp3, avi, m4v, ts, mpeg-4, flv, vob, ogg, ogv, webm, mov, wmv, asf, amv, mpg, mp2, mpeg, mpe, mpv, mpeg2"

    ' Avoid restarting the same stream
    'if m.video.content <> invalid and m.video.content.url = content.url then return

    content.HttpSendClientCertificates = true
    content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.EnableCookies()
    m.video.SetCertificatesFile("common:/certs/ca-bundle.crt")
    m.video.InitClientCertificates()

    m.video.content = content

    m.top.backgroundURI = "pkg:/images/rsgde_bg_hd.jpg"
    m.video.trickplaybarvisibilityauto = true

    m.video.control = "play"
end sub

' -------- SEARCH IMPLEMENTATION (triggered by InstantReplay) --------

' Open a keyboard dialog to enter a search term
sub showSearchDialog()
    if m.fullContent = invalid then return  ' nothing to search yet

    searchDialog = CreateObject("roSGNode", "KeyboardDialog")
    searchDialog.backgroundUri = "pkg:/images/rsgde_bg_hd.jpg"
    searchDialog.title = "Procurar Canais"

    searchDialog.buttons = ["Procurar", "Limpar Pesquisa", "Cancelar"]
    searchDialog.optionsDialog = true

    ' Start with the last search term, if any
    searchDialog.text = m.searchTerm
    searchDialog.keyboard.textEditBox.cursorPosition = len(searchDialog.text)
    searchDialog.keyboard.textEditBox.maxTextLength = 50

    m.top.dialog = searchDialog
    searchDialog.observeFieldScoped("buttonSelected", "onSearchDialogButton")
end sub

sub onSearchDialogButton()
    if m.top.dialog = invalid then return

    btn = m.top.dialog.buttonSelected

    if btn = 0 then  ' Search
        m.searchTerm = m.top.dialog.text
        FilterChannels(m.searchTerm)
        m.top.dialog.close = true
        m.list.SetFocus(true)
        m.video.translation = [800, 100]
        m.video.width = 960
        m.video.height = 540

    else if btn = 1 then  ' Clear
        m.searchTerm = ""
        FilterChannels("")  ' show all
        m.top.dialog.close = true

    else if btn = 2 then  ' Cancel
        m.top.dialog.close = true
    end if
end sub

' Filter the channel list in memory (no network, no task runs)
sub FilterChannels(term as String)
    if m.fullContent = invalid then return

    termLower = LCase(term)

    ' Empty search -> show original unfiltered list
    if termLower = "" then
        m.list.content = m.fullContent
        m.list.SetFocus(true)
        return
    end if

    filteredRoot = CreateObject("roSGNode", "ContentNode")

    children = m.fullContent.getChildren(-1, 0)
    if children = invalid then
        m.list.content = filteredRoot
        m.list.SetFocus(true)
        return
    end if

    ' Detect whether original content is flat or sectioned
    flat = true
    if children.Count() > 0 and children[0] <> invalid and children[0].getChild(0) <> invalid then
        flat = false
    end if

    if flat then
        ' Flat list: channels are direct children
        for each child in children
            if child <> invalid then
                title = ""
                if child.title <> invalid then
                    title = LCase(child.title)
                end if

                if Instr(title, termLower) > 0 then
                    filteredRoot.appendChild(child.Clone(true))
                end if
            end if
        end for
    else
        ' Sectioned list: iterate sections then items
        for each section in children
            if section <> invalid then
                items = section.getChildren(-1, 0)
                for each item in items
                    if item <> invalid then
                        title = ""
                        if item.title <> invalid then
                            title = LCase(item.title)
                        end if

                        if Instr(title, termLower) > 0 then
                            filteredRoot.appendChild(item.Clone(true))
                        end if
                    end if
                end for
            end if
        end for
    end if

    m.list.content = filteredRoot
    m.list.SetFocus(true)
end sub

' -------- PLAYLIST URL DIALOG (original) --------

sub showdialog()
    PRINT ">>>  Entrando no Teclado <<<"

    keyboarddialog = createObject("roSGNode", "KeyboardDialog")
    keyboarddialog.backgroundUri = "pkg:/images/rsgde_bg_hd.jpg"
    keyboarddialog.title = "Entre com a URL da Lista"

    keyboarddialog.buttons=["OK","Lista ManoTV", "Salvar"]
    keyboarddialog.optionsDialog=true

    m.top.dialog = keyboarddialog
    m.top.dialog.text = m.global.feedurl
    m.top.dialog.keyboard.textEditBox.cursorPosition = len(m.global.feedurl)
    m.top.dialog.keyboard.textEditBox.maxTextLength = 300

    KeyboardDialog.observeFieldScoped("buttonSelected","onKeyPress")  'we observe button ok/cancel, if so goto to onKeyPress sub
end sub

sub onKeyPress()
    if m.top.dialog.buttonSelected = 0 ' OK
        url = m.top.dialog.text
        m.global.feedurl = url
        m.save_feed_url.control = "RUN"
        m.top.dialog.close = true
        m.get_channel_list.control = "RUN"
    else if m.top.dialog.buttonSelected = 1 ' Set back to Demo
        m.top.dialog.text = "https://abre.ai/manotv3"
    else if m.top.dialog.buttonSelected = 2 ' Save
        m.global.feedurl = m.top.dialog.text
        m.save_feed_url.control = "RUN"
    end if
end sub
