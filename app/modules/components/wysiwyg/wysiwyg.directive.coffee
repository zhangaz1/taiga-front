###
# Copyright (C) 2014-2016 Andrey Antukh <niwi@niwi.nz>
# Copyright (C) 2014-2016 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014-2016 David Barragán Merino <bameda@dbarragan.com>
# Copyright (C) 2014-2016 Alejandro Alonso <alejandro.alonso@kaleidos.net>
# Copyright (C) 2014-2016 Juan Francisco Alcántara <juanfran.alcantara@kaleidos.net>
# Copyright (C) 2014-2016 Xavi Julian <xavier.julian@kaleidos.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/components/wysiwyg/wysiwyg.directive.coffee
###

taiga = @.taiga
bindOnce = @.taiga.bindOnce

Medium = ($translate, $confirm, $storage, wysiwygService, animationFrame, tgLoader, wysiwygCodeHightlighterService, wysiwygMentionService, analytics) ->

    isCodeBlockSelected = (range, elm) ->
        return !!$(range.endContainer).parentsUntil('.editor', 'code').length

    refreshCodeBlockHightlight = (elm) ->
        wysiwygCodeHightlighterService.refreshCodeLanguageSelectors(elm)

    removeCodeBlockAndHightlight = (range, elm) ->
        code = $(range.endContainer).closest('code')[0]
        pre = code.parentNode

        p = document.createElement('p')
        p.innerText = code.innerText

        pre.parentNode.replaceChild(p, pre)

        wysiwygCodeHightlighterService.removeCodeLanguageSelectors(elm)

    addCodeBlockAndHightlight = (range, elm) ->
        pre = document.createElement('pre')
        code = document.createElement('code')

        pre.appendChild(code)
        code.appendChild(range.extractContents())
        range.insertNode(pre)

        elm.checkContentChanged()

        wysiwygCodeHightlighterService.addCodeLanguageSelectors(elm)


    AlignRightButton = MediumEditor.extensions.button.extend({
        name: 'rtl',
        init: () ->
            option = _.find this.base.options.toolbar.buttons, (it) ->
                it.name == 'rtl'

            this.button = this.document.createElement('button')
            this.button.classList.add('medium-editor-action')
            this.button.innerHTML = option.contentDefault || '<b>RTL</b>'
            this.button.title = 'RTL'
            this.on(this.button, 'click', this.handleClick.bind(this))

        getButton: () ->
            return this.button
        handleClick: (event) ->
            range = MediumEditor.selection.getSelectionRange(document)
            if range.commonAncestorContainer.parentNode.style.textAlign == 'right'
                document.execCommand('justifyLeft', false)
            else
                document.execCommand('justifyRight', false)

    })

    getIcon = (icon) ->
        return """<svg class="icon icon-#{icon}">
            <use xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="##{icon}"></use>
        </svg>"""

    # MediumEditor extension to add <code>
    CodeButton = MediumEditor.extensions.button.extend({
        name: 'code',
        init: () ->
            option = _.find this.base.options.toolbar.buttons, (it) ->
                it.name == 'code'

            this.button = this.document.createElement('button')
            this.button.classList.add('medium-editor-action')
            this.button.innerHTML = option.contentDefault || '<b>Code</b>'
            this.button.title = 'Code'
            this.on(this.button, 'click', this.handleClick.bind(this))

        getButton: () ->
            return this.button

        tagNames: ['code']

        handleClick: (event) ->
            range = MediumEditor.selection.getSelectionRange(self.document)

            if isCodeBlockSelected(range, this.base)
                removeCodeBlockAndHightlight(range, this.base)
            else
                addCodeBlockAndHightlight(range, this.base)
    })

    CustomPasteHandler = MediumEditor.extensions.paste.extend({
        doPaste: (pastedHTML, pastedPlain, editable) ->
            html = MediumEditor.util.htmlEntities(pastedPlain);

            MediumEditor.util.insertHTMLCommand(this.document, html);
    })

    # bug
    # <pre><code></code></pre> the enter key press doesn't work
    oldIsBlockContainer = MediumEditor.util.isBlockContainer

    MediumEditor.util.isBlockContainer = (element) ->
        if !element
            return oldIsBlockContainer(element)

        if element.tagName
            tagName = element.tagName
        else
            tagName = element.parentNode.tagName

        if tagName.toLowerCase() == 'code'
            return true

        return oldIsBlockContainer(element)

    link = ($scope, $el, $attrs) ->
        mediumInstance = null
        editorMedium = $el.find('.medium')
        editorMarkdown = $el.find('.markdown')

        isEditOnly = !!$attrs.$attr.editonly
        notPersist = !!$attrs.$attr.notPersist

        $scope.required = !!$attrs.$attr.required
        $scope.editMode = isEditOnly || false
        $scope.mode = $storage.get('editor-mode', 'html')

        wysiwygService.loadEmojis()

        setHtmlMedium = (markdown) ->
            html = wysiwygService.getHTML(markdown)
            editorMedium.html(html)

        $scope.setMode = (mode) ->
            $storage.set('editor-mode', mode)

            if mode == 'markdown'
                updateMarkdownWithCurrentHtml()
            else
                setHtmlMedium($scope.markdown)

            $scope.mode = mode
            mediumInstance.trigger('editableBlur', {}, editorMedium[0])

        $scope.save = () ->
            if $scope.mode == 'html'
                updateMarkdownWithCurrentHtml()

            return if $scope.required && !$scope.markdown.length

            $scope.saving  = true
            $scope.outdated = false

            $scope.onSave({text: $scope.markdown, cb: saveEnd})

            return

        $scope.cancel = () ->
            if !isEditOnly
                $scope.editMode = false

            if notPersist
                clean()
            else if $scope.mode == 'html'
                setHtmlMedium($scope.content)

            $scope.markdown = $scope.content

            discardLocalStorage()
            mediumInstance.trigger('blur', {}, editorMedium[0])
            $scope.outdated = false

            $scope.onCancel()

            return

        clean = () ->
            $scope.markdown = ''
            editorMedium.html('')

        refreshExtras = () ->
            animationFrame.add () ->
                if $scope.mode == 'html'
                    if $scope.editMode
                        wysiwygCodeHightlighterService.addCodeLanguageSelectors(mediumInstance)
                        wysiwygCodeHightlighterService.removeHightlighter(mediumInstance.elements[0])
                    else
                        wysiwygCodeHightlighterService.addHightlighter(mediumInstance.elements[0])
                        wysiwygCodeHightlighterService.removeCodeLanguageSelectors(mediumInstance)
                else
                    wysiwygCodeHightlighterService.removeHightlighter(mediumInstance.elements[0])
                    wysiwygCodeHightlighterService.removeCodeLanguageSelectors(mediumInstance)

        saveEnd = () ->
            $scope.saving  = false

            if !isEditOnly
                $scope.editMode = false

            if notPersist
                clean()

            discardLocalStorage()
            mediumInstance.trigger('blur', {}, editorMedium[0])

            analytics.trackEvent('develop', 'save wysiwyg', $scope.mode, 1)

        uploadEnd = (name, url) ->
            if taiga.isImage(name)
                mediumInstance.pasteHTML("<img src='" + url + "' /><br/>")
            else
                name = $('<div/>').text(name).html()
                mediumInstance.pasteHTML("<a target='_blank' href='" + url + "'>" + name + "</a><br/>")

        isOutdated = () ->
            store = $storage.get($scope.storageKey)

            if store && store.version && store.version != $scope.version
                return true

            return false

        isDraft = () ->
            store = $storage.get($scope.storageKey)

            if store
                return true

            return false

        getCurrentContent = () ->
            store = $storage.get($scope.storageKey)

            if store
                return store.text

            return $scope.content

        discardLocalStorage = () ->
            $storage.remove($scope.storageKey)

        cancelWithConfirmation = () ->
            if $scope.content == $scope.markdown
                $scope.cancel()

                document.activeElement.blur()
                document.body.click()

                return null

            title = $translate.instant("COMMON.CONFIRM_CLOSE_EDIT_MODE_TITLE")
            message = $translate.instant("COMMON.CONFIRM_CLOSE_EDIT_MODE_MESSAGE")

            $confirm.ask(title, null, message).then (askResponse) ->
                $scope.cancel()
                askResponse.finish()

        # firefox adds br instead of new lines inside <code>, taiga must replace the br by \n before sending to the server
        replaceCodeBrToNl = () ->
            html = $('<div></div>').html(editorMedium.html())
            html.find('code br').replaceWith('\n')

            return html.html()

        updateMarkdownWithCurrentHtml = () ->
            html = replaceCodeBrToNl()
            $scope.markdown = wysiwygService.getMarkdown(html)

        localSave = (markdown) ->
            if $scope.storageKey
                store = {}
                store.version = $scope.version || 0
                store.text = markdown
                $storage.set($scope.storageKey, store)

        change = () ->
            if $scope.mode == 'html'
                updateMarkdownWithCurrentHtml()
                wysiwygCodeHightlighterService.updateCodeLanguageSelector(mediumInstance)

            localSave($scope.markdown)

            $scope.onChange({markdown: $scope.markdown})

        throttleChange = _.throttle(change, 200)

        create = (text, editMode=false) ->
            if text.length
                html = wysiwygService.getHTML(text)
                editorMedium.html(html)

            mediumInstance = new MediumEditor(editorMedium[0], {
                targetBlank: true,
                imageDragging: false,
                placeholder: {
                    text: $scope.placeholder
                },
                toolbar: {
                    buttons: [
                        {
                            name: 'bold',
                            contentDefault: getIcon('editor-bold')
                        },
                        {
                            name: 'italic',
                            contentDefault: getIcon('editor-italic')
                        },
                        {
                            name: 'strikethrough',
                            contentDefault: getIcon('editor-cross-out')
                        },
                        {
                            name: 'anchor',
                            contentDefault: getIcon('editor-link')
                        },
                        {
                            name: 'image',
                            contentDefault: getIcon('editor-image')
                        },
                        {
                            name: 'orderedlist',
                            contentDefault: getIcon('editor-list-n')
                        },
                        {
                            name: 'unorderedlist',
                            contentDefault: getIcon('editor-list-o')
                        },
                        {
                            name: 'h1',
                            contentDefault: getIcon('editor-h1')
                        },
                        {
                            name: 'h2',
                            contentDefault: getIcon('editor-h2')
                        },
                        {
                            name: 'h3',
                            contentDefault: getIcon('editor-h3')
                        },
                        {
                            name: 'quote',
                            contentDefault: getIcon('editor-quote')
                        },
                        {
                            name: 'removeFormat',
                            contentDefault: getIcon('editor-no-format')
                        },
                        {
                            name: 'rtl',
                            contentDefault: getIcon('editor-rtl')
                        },
                        {
                            name: 'code',
                            contentDefault: getIcon('editor-code')
                        }
                    ]
                },
                extensions: {
                    paste: new CustomPasteHandler(),
                    code: new CodeButton(),
                    autolist: new AutoList(),
                    alignright: new AlignRightButton(),
                    mediumMention: new MentionExtension({
                        getItems: (mention, mentionCb) ->
                            wysiwygMentionService.search(mention).then(mentionCb)
                    })
                }
            })

            $scope.changeMarkdown = throttleChange

            mediumInstance.subscribe 'editableInput', (e) ->
                $scope.$applyAsync(throttleChange)

            mediumInstance.subscribe "editableClick", (e) ->
                e.stopPropagation()

                if e.target.href
                    window.open(e.target.href)

            mediumInstance.subscribe 'focus', (event) ->
                $scope.$applyAsync () ->
                    if !$scope.editMode
                        $scope.editMode = true

            mediumInstance.subscribe 'editableDrop', (event) ->
                $scope.onUploadFile({files: event.dataTransfer.files, cb: uploadEnd})

            editorMedium.on 'keydown', (e) ->
                code = if e.keyCode then e.keyCode else e.which
                range = MediumEditor.selection.getSelectionRange(document)
                codeBlock = isCodeBlockSelected(range, document)
                selection = window.getSelection()

                if code == 13 && !e.shiftKey && selection.focusOffset == _.trimEnd(selection.focusNode.textContent).length
                    e.preventDefault()
                    document.execCommand('insertHTML', false, '<p id="last-p"><br/></p>')

                    lastP = $('#last-p').attr('id', '')

                    range = document.createRange()
                    range.selectNodeContents(lastP[0])
                    range.collapse(true);

                    MediumEditor.selection.selectRange(document, range)

            mediumInstance.subscribe 'editableKeydown', (e) ->
                code = if e.keyCode then e.keyCode else e.which

                mention = $('.medium-mention')

                if (code == 40 || code == 38) && mention.length
                    e.stopPropagation()
                    e.preventDefault()

                    return

                if $scope.editMode && code == 27
                    e.stopPropagation()
                    $scope.$applyAsync(cancelWithConfirmation)
                else if code == 27
                    editorMedium.blur()

            $scope.editMode = editMode

            $scope.$applyAsync(refreshExtras)

            $scope.$watch () ->
                return $scope.mode + ":" + $scope.editMode
            , () ->
                $scope.$applyAsync(refreshExtras)

        unwatch = $scope.$watch 'content', (content) ->
            if !_.isUndefined(content)
                $scope.outdated = isOutdated()

                if !mediumInstance && isDraft()
                    $scope.editMode = true

                if $scope.markdown == content
                    return

                content = getCurrentContent()

                $scope.markdown = content

                if mediumInstance
                    mediumInstance.destroy()

                if tgLoader.open()
                    unwatchLoader = tgLoader.onEnd () ->
                        create(content, $scope.editMode)
                        unwatchLoader()
                else
                    create(content, $scope.editMode)

                unwatch()

        $scope.$on "$destroy", () ->
            if mediumInstance
                wysiwygCodeHightlighterService.removeCodeLanguageSelectors(mediumInstance)
                mediumInstance.destroy()

    return {
        templateUrl: "common/components/wysiwyg-toolbar.html",
        scope: {
            placeholder: '@',
            version: '<',
            storageKey: '<',
            content: '<',
            onCancel: '&',
            onSave: '&',
            onUploadFile: '&',
            onChange: '&'
        },
        link: link
    }

angular.module("taigaComponents").directive("tgWysiwyg", [
    "$translate",
    "$tgConfirm",
    "$tgStorage",
    "tgWysiwygService",
    "animationFrame",
    "tgLoader",
    "tgWysiwygCodeHightlighterService",
    "tgWysiwygMentionService",
    "$tgAnalytics",
    Medium
])
