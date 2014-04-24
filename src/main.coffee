get = (arr, index) ->
    if(index < 0)
        arr[arr.length + index]
    else
        arr[index]

unless window.requestAnimationFrame
  window.requestAnimationFrame = (callback) ->
    currTime = new Date().getTime()
    timeToCall = Math.max(0, 16 - (currTime - lastTime))
    id = window.setTimeout
    (->
      callback currTime + timeToCall
      , timeToCall
    )
    lastTime = currTime + timeToCall
    id

syntax = require('./syntax')
trx = require('tiny-rx')
u = require('./util')
_ = require('lodash')
keyHelper = require('./keys')
keys = require('./keys')

class Vim
    constructor: ()->
        self = @
        Object.defineProperties @,
            '$cursor':
                get: -> document.querySelector('.cursor')
            '$editor':
                get: -> document.querySelector('.editor')
            '$body':
                get: -> document.querySelector('body')
            '$search':
                get: -> document.querySelector('.search-field')
            '$cursorContainer':
                get: -> document.querySelector('.cursor-container')
            'x':
                get: -> self.cursorPosition.value()[0]
                set: (x)-> self.cursorPosition.value([x, @y])
            'y':
                get: -> self.cursorPosition.value()[1]
                set: (y)-> self.cursorPosition.value([@x, y]) if @lines.length-1 >= y
            'currentLine':
                get: -> self.lines[self.cursorPosition.value()[1]]
            'lines':
                get: -> self._lines.value().split('\n')
                set: (val) -> self._lines.value(val.join('\n'))
            'mode':
                get: -> @_mode.value()
                set: (val) -> @_mode.value(val)
            'searchString':
                get: -> @_searchString.value()
                set: (val)-> 
                    @$search.textContent = val
                    @_searchString.value(val)

        @$inputBuffer = document.getElementById('input-buffer')
        @_mode = trx.createProperty('visual')
        @_searchString = trx.createProperty('')
        @_yankRegister = trx.createProperty([])
        @_lines = trx.createProperty(@$editor.textContent)
        @isCursorIdle = trx.createProperty()
        @isCursorIdle.value(true)
        @inputEvents = trx.fromDomEvent('input', @$inputBuffer)
            .map((e)-> 
                e.char = e.target.value[e.target.value.length-1]
                e.target.value = ''
                e
            )

        @keydownEvents = trx.fromDomEvent('keydown', @$inputBuffer)
            .map((e)-> 
                keys[''+e.keyCode]
            ).truethy()

        #Always retain focus on invisible input-buffer element
        trx.fromDomEvent('blur', @$inputBuffer).subscribe((e)->
            e.target.focus()
        )

        @init()

    render:(x = @x,y = @y) =>
        result = @lines.join('\n')

        if(@searchString.length > 0)
            re = new RegExp('('+@searchString+')', 'gm')
            result = result.replace(re, '<span class="highlighted">$1</span>')

        r = syntax.html(result)
        @$editor.innerHTML = result

        cursorContainerHtml = []
        for l, i in @lines
            if @y == i
                cursorContainerHtml.push l.substr(0,x) + @$cursor.outerHTML + l.substr(x)
            else
                cursorContainerHtml.push l
        @$cursorContainer.innerHTML = cursorContainerHtml.join('\n')


    gotoEnd: () => @x = @currentLine.length-1

    prevWord: () => @skipRegex(/[^\s\.]+(?:\s+|\.)/gi, true)

    gotoStart: () => @x = 0

    insert: (val) =>
        line = @lines[@y]
        splitLine = (line.substr(0, @x) + val + line.substr(@x)).split('\n')
        lines = @lines
        lines.splice(@y,1)
        y = @y
        for l,i in splitLine
            lines.splice(y+i, 0, l)
        @lines = lines
        @x++ unless splitLine.length > 1
        @render()

    newLine: () =>
        lines = @lines
        @y++
        lines.splice(@y,0, '')
        @lines = lines
        @render()

    delete: () =>
        lines = @lines
        console.log lines[@y] + '}'
        lines[@y] = lines[@y].substr(0, @x-1) + lines[@y].substr(@x)
        console.log lines[@y] + '}'
        @lines = lines
        @x--
        @render()

    cutLine: () =>
        lines = @lines
        lines.splice(@y, 1)
        @y-- if @lines.length - 1 <= @y
        @lines = lines
        @render()

    skipRegex: (regex, reverse) =>
        y = @y
        unless reverse 
            line = @lines[y].slice(@x)
            results = line.match(regex)
            if(!results || results.length < 2)
                y++
                line = @lines[y]
                results = regex.exec(line)
                if(results && results.length > 0)
                    @x=0
                    @y++
            
            @x+= results?[0].length || 0
        else
            line = @lines[y].slice(0, @x)
            results = line.match(regex)
            if(!results)
                y--
                line = @lines[y]
                results = line.match(regex)
                if(results.length > 0)
                    @x=line.length-1
                    @y--

            result = results?[results.length-1].length || 0
            @x-= result

    nextWord: ->
        @.skipRegex(/[^\s\.]*[\s\.]+/gi)
        undefined

    init: () =>
        # Events from keyboard, add a time event so we can 
        self = @
        tickerEvents = trx.createStream()

        ticker = setInterval(()->
            tickerEvents.publish({type: 'tick', timeStamp: new Date})
        , 300)

        @inputEvents.merge(tickerEvents).createHistory(2)
            .filter((events)-> events.length > 1)
            .map((events)-> 
                events[1].timeStamp - events[0].timeStamp
            ).createProperty((isIdle, time)->
                if(time > 300)
                    isIdle = true
                else
                    isIdle = false
            ).subscribe((isIdle)->
                if (isIdle)
                    self.$cursor.classList.add('idle')
                else 
                    self.$cursor.classList.remove('idle')
                
            )

        @inputHistory = @inputEvents.createHistory()

        @_mode.subscribe((modeName)->
            self.$body.className = modeName
        )

        # RIGHT
        right = @inputEvents.filter(()-> self.mode == 'visual').filter((e)-> 
            e.char == 'l'
        ).map([1,0])

        # LEFT
        left = @inputEvents.filter(()-> self.mode == 'visual').filter((e)-> 
            e.char == 'h'
        ).map([-1,0])

        # DOWN
        down = @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'j'
        ).map([0,1])

        # UP
        up = @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'k'
        ).map([0,-1])

        # NEXT WORD
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'w'
        ).subscribe((e)->
            self.nextWord()
        )

        # PREVIOUS WORD
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'b'
        ).subscribe((e)-> 
            self.prevWord()
        )

        #END OF LINE
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == '$'
        ).subscribe((e)->
            self.gotoEnd()
        )

        #START OF LINE
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == '0'
        ).subscribe((e)->
            self.gotoStart()
        )

        #SEARCH
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == '/'
        ).subscribe((e)->
            requestAnimationFrame(()->
                self.mode = 'search'
            )
        )

        #INPUT
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'i' || e.char == 'I'
        ).subscribe((e)->
            if e.char == 'I'
                self.gotoStart()
                
            requestAnimationFrame(()->
                self.mode = 'input'
            )
        )

        #INSERT
        @inputEvents.filter(()-> self.mode == 'input').subscribe((e)->
            self.insert(e.char) if e.char && e.char.length > 0
        )

        #INSERT NEWLINE ABOVE
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'O'
        ).subscribe(()->
            self.x=0
            self.insert('\n')
            self.mode = 'input'
        )

        #INSERT NEWLINE BELOW
        @inputEvents.filter(()-> self.mode == 'visual').filter((e)->
            e.char == 'o'
        ).subscribe(()->
            self.newLine()
            self.mode = 'input'
        )


        #DELETE LINE - dd
        @inputHistory.filter(
            (events)-> 
                events.length > 1 &&
                self.mode == 'visual' && 
                get(events, -1).char + get(events, -2).char == 'dd')
            .subscribe((e)->
                self.inputHistory.reset()
                self.cutLine()
            )

        #DELETE LAST CHARACTER
        @keydownEvents.filter((key)-> self.mode == 'input' && key == 'del').subscribe(()->
            console.log 'self delete'
            self.delete()
        )

        #NEW LINEBREAK - ENTER
        @keydownEvents.filter((key)-> self.mode == 'input' && key == 'enter').subscribe(()->
            console.log 'enter'
            self.insert('\n')
            self.y++
            self.gotoStart()
        )

        #ESCAPE
        @keydownEvents.filter((key)-> 
            key == 'esc'
        ).subscribe(()-> 
            if(self.mode == 'search')
                self.searchString = ''
            self.mode = 'visual'
        )

        #ENTER VISUAL
        @keydownEvents
            .filter((key)-> self.mode == 'visual' && key == 'enter')
            .subscribe(()-> 
                self.x = 0
                self.y++
                self.nextWord()
            )

        @keydownEvents
            .filter((key)-> key == 'del' && self.mode == 'search')
            .subscribe(()->
                self.searchString = self.searchString.substr(0, self.searchString.length-1)
            )

        #change searchstring while typing
        @inputEvents.filter(()-> self.mode == 'search').subscribe((e)->
            self.searchString += e.char if e.char
        )

        @_searchString.subscribe((string)-> 
            self.render()
        )

        @cursorPosition = left.merge([right, up, down]).createProperty((position, vector)-> 
            if(position[0]+vector[0] < 0)
                position[0] = 0
            else
                position[0]+=vector[0]
            if(position[1]+vector[1] < 0)
                position[1] = 0
            else if(position[1]+vector[1] >= self.lines.length)
                position[1] = self.lines.length - 1
            else
                position[1]+=vector[1]
            position
        , [0,0])

        @cursorPosition.subscribe((position)->
            self.render(position[0], position[1])
        )

        @render()

new Vim
