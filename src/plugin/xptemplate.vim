" XPTEMPLATE ENGIE:
"   snippet template engine
" VERSION: 0.3.9.0
" BY: drdr.xp | drdr.xp@gmail.com
"
" MARK USED:
"   <, >  visual marks
"
" USAGE: "{{{
"   1) vim test.js
"   2) to type:
"     for<C-\>
"     generating a for-loop template:
"     for ( i = 0; i < n; ++i ) { 
"
"     }
"     using <TAB> navigate through
"     template
" "}}}
"
" BUG: "{{{
"
" "}}}
"
" TODOLIST: "{{{
" TODO escaped mark in snippet '`' and '^' and in nested.
" TODO snippets bundle and bundle selection
" TODO snippet-file scope XSET
" TODO block context check
" TODO eval default value in-time
" TODO without template rendering, xpmark update complains error.
" TODO ontime repetition
" TODO in windows & in select mode to trigger wrapped or normal?
" TODO change on previous item
" TODO implement wrapping in more natural way. nested maybe.
" TODO as function call template
" TODO highlight all pending item instead of using mark
" TODO item popup: repopup
" TODO install guide
" TODO do not let xpt throw error if calling undefined s:f.function..
" TODO buffer/snippet scope template setting.
" TODO simple place holder : just a postion waiting for user input
" TODO undo
" TODO test more : char before snippet, char after, last cursor position,
" TODO wrapping on different visual mode
" TODO prefixed template trigger
" TODO class-style
" TODO simplify if no need to popup, popup session
" TODO on the first time template rendering, replace all vars with its value.
" TODO pre-build expression to evaluate
" TODO separately store wrapped templates and normal ones
" TODO match snippet names from middle
" TODO snippets bundle and bundle selection
" TODO 'completefunc' to re-popup item menu. Or using <tab> to force popup showing
"
" "}}}
"
" 


if exists("g:__XPTEMPLATE_VIM__")
    finish
endif
let g:__XPTEMPLATE_VIM__ = 1


com! XPTgetSID let s:sid =  matchstr("<SID>", '\zs\d\+_\ze')
XPTgetSID
delc XPTgetSID




" runtime plugin/position.vim
runtime plugin/debug.vim
runtime plugin/xptemplate.util.vim
runtime plugin/mapstack.vim
runtime plugin/xpreplace.vim
runtime plugin/xpmark.vim
runtime plugin/xpopup.vim
runtime plugin/xptemplate.conf.vim


let s:log = CreateLogger( 'debug' )

call XPRaddPreJob( 'XPMupdateCursorStat' )
call XPRaddPostJob( 'XPMupdateSpecificChangedRange' )
" call XPMsetUpdateStrategy( 'manual' )  
" call XPMsetUpdateStrategy( 'auto' ) 
call XPMsetUpdateStrategy( 'normalMode' ) 


fun! XPTmarkCompare( o, markToAdd, existedMark )
    call s:log.Log( 'compare : ' . a:markToAdd . ' and ' . a:existedMark )
    let renderContext = s:getRenderContext()

    if renderContext.phase == 'rendering' 
        let [ lm, rm ] = [ a:o.changeLikelyBetween.start, a:o.changeLikelyBetween.end ]
        if a:existedMark ==# rm
            return -1
        endif
    
    elseif renderContext.action == 'build' && has_key( renderContext, 'buildingMarkRange' ) 
                \&& renderContext.buildingMarkRange.end ==  a:existedMark
        call s:log.Debug( a:markToAdd . ' < ' . a:existedMark )
        return -1
    endif

    call s:log.Debug( a:markToAdd . ' > ' . a:existedMark )
    return 1
endfunction


" escape rule:
" 0 a
" 1 \a
" 3 \\\a
" 7 \\\\\\\a
"
" 2 \\a
" 5 \\\\\a
"
" 2*n + 1

let s:NullDict              = {}
let s:NullList              = []

let s:ftNeedToRedraw        = '\<\%(' . join([ 'perl' ], '\|') . '\)\>'
let s:unescapeHead          = '\v(\\*)\1\\?\V'

let s:nonEscaped            = '\%(' . '\%(\[^\\]\|\^\)' . '\%(\\\\\)\*' . '\)' . '\@<='
let s:escaped               = '\%(' . '\%(\[^\\]\|\^\)' . '\%(\\\\\)\*' . '\)' . '\@<=' . '\\'

let s:stripPtn              = '\V\^\s\*\zs\.\*'
let s:wrappedName           = "wrapped"
let g:XPTemplateSettingPrototype  = { 
            \    'preValues'        : { 'cursor' : "\n" . '$CURSOR_PH' }, 
            \    'defaultValues'    : {}, 
            \    'postFilters'      : {}, 
            \    'comeFirst'        : [], 
            \    'comeLast'         : [], 
            \}


fun! g:XPTapplyTemplateSettingDefaultValue( setting ) "{{{
    let s = a:setting
    call s:SetIfEmpty( s,           'postQuoter', { 'start' : '{{', 'end' : '}}' } )
    call s:SetIfEmpty( s.preValues, 'cursor', '$CURSOR_PH' )
endfunction "}}}

let s:renderContextPrototype      = {
            \    'tmpl'              : {},
            \    'evalCtx'           : {},
            \    'phase'             : 'uninit',
            \    'action'            : '',
            \    'markNamePre'       : '', 
            \    'item'              : {}, 
            \    'leadingPlaceHolder' : {}, 
            \    'step'              : [],
            \    'namedStep'         : {},
            \    'processing'        : 0,
            \    'marks'             : {
            \       'tmpl'           : {'start' : '', 'end' : ''} },
            \    'itemDict'          : {},
            \    'itemList'          : [],
            \    'lastContent'       : '',
            \    'lastTotalLine'     : 0, 
            \    'lastFollowingSpace': '', 
            \}
let s:vrangeClosed = "\\%>'<\\%<'>"
let s:vrange       = '\V' . '\%(' . '\%(' . s:vrangeClosed .'\)' .  '\|' . "\\%'<\\|\\%'>" . '\)'

let s:plugins = {}
let s:plugins.beforeRender = []
let s:plugins.afterRender = []

let s:plugins.beforeFinish = []
let s:plugins.afterFinish = []

let s:plugins.beforeApplyPredefined = []
let s:plugins.afterApplyPredefined = []

let s:plugins.beforeInitItem = []
let s:plugins.afterInitItem = []

let s:plugins.beforeNextItem = []
let s:plugins.afterNextItem = []

let s:plugins.beforeUpdate = []
let s:plugins.afterUpdate = []

let s:priorities = {'all' : 64, 'spec' : 48, 'like' : 32, 'lang' : 16, 'sub' : 8, 'personal' : 0}
let s:priPtn = 'all\|spec\|like\|lang\|sub\|personal\|\d\+'

let s:f = {}
let g:XPT = s:f




let s:buildingSeqNr = 0




let s:pumCB = {}

fun! s:pumCB.onEmpty(sess) "{{{
    return ""
endfunction "}}}

fun! s:pumCB.onOneMatch(sess) "{{{
  call s:log.Log( "match one:".a:sess.matched )
  return s:DoStart(a:sess)
endfunction "}}}

let s:ItemPumCB = {}

fun! s:ItemPumCB.onOneMatch(sess) "{{{

    " TODO  next item is better?
    call s:XPTupdate()

    return s:finishCurrentAndGotoNextItem( '' )
    " return ""
endfunction "}}}


" ===================================================
" API
" ===================================================

" which letter can be used in template name other than 'iskeyword'
fun! XPTemplateKeyword(val) "{{{
    let x = g:XPTobject()

    " word characters are already valid.
    let val = substitute(a:val, '\w', '', 'g')

    let keyFilter = 'v:val !~ ''\V\[' . escape(val, '\]') . ']'' '

    call filter( x.keywordList, keyFilter )
    let x.keywordList += split( val, '\s*' )

    let x.keyword = '\[' . escape( join( x.keywordList, '' ), '\]' ) . ']'

endfunction "}}}

fun! XPTemplatePriority(...) "{{{
    let x = g:XPTobject()
    let p = a:0 == 0 ? 'lang' : a:1

    let x.snipFileScope.priority = s:ParsePriorityString(p)
endfunction "}}}

fun! XPTemplateMark(sl, sr) "{{{
  call s:log.Debug( 'XPTemplateMark called with:' . string( [ a:sl, a:sr ] ) )
    let xp = g:XPTobject().snipFileScope.ptn
    let xp.l = a:sl
    let xp.r = a:sr
    call s:RedefinePattern()
endfunction "}}}

fun! XPTemplateIndent(p) "{{{
    let x = g:XPTobject().snipFileScope.indent
    call s:ParseIndent(x, a:p)
endfunction "}}}

fun! XPTmark() "{{{
    let renderContext = s:getRenderContext()
    let xp = renderContext.tmpl.ptn
    return [ xp.l, xp.r ]
endfunction "}}}

fun! XPTcontainer() "{{{
    return [g:XPTobject().vars, g:XPTobject().vars]
endfunction "}}}

" deprecated
fun! g:XPTvars() "{{{
    return g:XPTobject().vars
endfunction "}}}

" deprecated
fun! g:XPTfuncs() "{{{
    return g:XPTobject().funcs
endfunction "}}}


fun! XPTemplateAlias( name, toWhich, setting ) "{{{
    " TODO wrapping templates
    let xptObj = g:XPTobject()
    let xt = xptObj.normalTemplates

    if has_key( xt, a:toWhich )
        let xt[ a:name ] = deepcopy( xt[ a:toWhich ] )
        let xt[ a:name ].name = a:name
        call s:ParseTemplateSetting( xptObj, a:setting )
        call g:xptutil.DeepExtend( xt[ a:name ].setting, a:setting )
    endif

endfunction "}}}


" ********* XXX ********* 
fun! XPTemplate(name, str_or_ctx, ...) " {{{

    " @param String name	 		tempalte name
    " @param String context			[optional] context syntax name
    " @param String|List|FunCRef str	template string

    let x         = g:XPTobject()
    let templates = g:XPTobject().normalTemplates
    let xp        = g:XPTobject().snipFileScope.ptn

    " using dictionary member instead of direct variable for type limit
    let foo       = { 'snip' : '' }

    let templateSetting = deepcopy(g:XPTemplateSettingPrototype)

    if a:0 == 0          " no syntax context
        let foo.snip = a:str_or_ctx

    elseif a:0 == 1      " with syntax context
        call extend( templateSetting, a:str_or_ctx, 'force' )
        let foo.snip = a:1

    endif

    call g:XPTapplyTemplateSettingDefaultValue( templateSetting )



    let prio =  has_key(templateSetting, 'priority') ? 
                \ s:ParsePriorityString(templateSetting.priority) :
                \ x.snipFileScope.priority


    " existed template is not overrided.
    if has_key(templates, a:name) && templates[a:name].priority <= prio
        return
    endif



    call s:CleanupSnippet( x, foo )

    let isWrapped = type(foo.snip) != type(function("tr")) && foo.snip =~ '\V' . xp.lft . s:wrappedName . xp.rt


    call s:log.Log("tmpl :name=".a:name." priority=".prio)
    let templates[a:name] = {
                \ 'name'        : a:name,
                \ 'tmpl'        : foo.snip,
                \ 'priority'    : prio,
                \ 'setting'     : templateSetting,
                \ 'ptn'         : deepcopy(g:XPTobject().snipFileScope.ptn),
                \ 'wrapped'     : isWrapped, 
                \}

    call s:InitTemplateObject( x, templates[ a:name ] )

endfunction " }}}

fun! s:CleanupSnippet( xptObj, foo ) "{{{
    if type( a:foo.snip ) == type( 'tr' )
        return a:foo.snip
    endif


    let foo = a:foo
    if type(foo.snip) == type([])
        let foo.snip = join(foo.snip, "\n")

    endif

    if type( foo.snip ) == type( '' )
        let tabspace = repeat( ' ', &l:tabstop )
        " let foo.snip = substitute( foo.snip, '\t', tabspace, 'g' )
    endif

    " let ptn = a:xptObj.snipFileScope.ptn
    " let foo.snip = g:xptutil.UnescapeChar( foo.snip, ptn.l . ptn.r )

    return foo.snip

endfunction "}}}

fun! s:InitTemplateObject( xptObj, tmplObj ) "{{{

    call s:ParseTemplateSetting( a:xptObj, a:tmplObj.setting )

    if type( a:tmplObj.tmpl ) == type( '' )
        let a:tmplObj.tmpl = s:parseQuotedPostFilter( a:tmplObj )
    endif

    call s:log.Debug( 'create template name=' . a:tmplObj.name . ' tmpl=' . a:tmplObj.tmpl )

    call s:addCursorToComeLast(a:tmplObj.setting)
    call s:initItemOrderDict( a:tmplObj.setting )




    let a:tmplObj.setting.defaultValues.cursor = 'Finish()'
endfunction "}}}


fun! s:ParseTemplateSetting( xptObj, setting ) "{{{
    let setting = a:setting


    let idt = deepcopy(a:xptObj.snipFileScope.indent)

    if has_key(setting, 'indent')
        call s:ParseIndent(idt, setting.indent)
    endif

    let setting.indent = idt


    call s:GetHint(setting)

    call s:ParsePostQuoter( setting )

endfunction "}}}

fun! s:ParsePostQuoter( setting ) "{{{
    if !has_key( a:setting, 'postQuoter' ) 
                \ || type( a:setting.postQuoter ) == type( {} )
        return
    endif

    
    let quoters = split( a:setting.postQuoter, ',' )
    if len( quoters ) < 2
        throw 'postQuoter must be separated with ","! :' . a:setting.postQuoter
    endif

    let a:setting.postQuoter = { 'start' : quoters[0], 'end' : quoters[1] }
endfunction "}}}

fun! s:addCursorToComeLast(setting) "{{{
  let comeLast = copy( a:setting.comeLast )

  let cursorItem = filter( comeLast, 'v:val == "cursor"' )
  call s:log.Debug( 'has cursor item?:' . string( cursorItem ) )

  if cursorItem == []
    call add( a:setting.comeLast, 'cursor' )
  endif

  call s:log.Debug( 'has cursor item?:' . string( a:setting.comeLast ) )

endfunction "}}}

fun! s:initItemOrderDict( setting ) "{{{
    " create name-to-index dictionary
    " TODO move me to template creation phase

    let setting = a:setting
    let [ first, last ] = [ setting.comeFirst, setting.comeLast ]

    let setting.firstDict = {}
    let setting.lastDict = {}

    " Skeleton list for creating ordered item list.
    " Each element of it is a position holder.
    let setting.firstListSkeleton = []
    let setting.lastListSkeleton = []

    let [i, len] = [ 0, len( first ) ]
    while i < len
        let setting.firstDict[ first[ i ] ] = i
        call add( setting.firstListSkeleton, {} )
        let i += 1
    endwhile
    
    let [i, len] = [ 0, len( last ) ]
    while i < len
        let setting.lastDict[ last[ i ] ] = i
        call add( setting.lastListSkeleton, {} )
        let i += 1
    endwhile


    call s:log.Log( 'firstDict' . string( setting.firstDict ) )
    call s:log.Log( 'lastDict' . string( setting.lastDict ) )

endfunction "}}}

fun! XPTreload() "{{{
  try
    unlet b:__xpt_loaded
    unlet b:xptemplateData
  catch /.*/
  endtry
  e
endfunction "}}}

fun! XPTgetAllTemplates() "{{{
    return copy( g:XPTobject().normalTemplates )
endfunction "}}}


fun! XPTemplatePreWrap(wrap) "{{{
    let x = g:XPTobject()
    let x.wrap = a:wrap

    if x.wrap[-1:-1] == "\n"
        let x.wrap = x.wrap[0:-2]
        " TODO use XPreplace
        let @" = "\n"
        normal! ""P
    endif

    let x.wrapStartPos = col(".")

    if g:xptemplate_strip_left
        let x.wrap = substitute(x.wrap, '^\s*', '', '')
    endif

    let ppr = s:Popup("", x.wrapStartPos)

    call s:log.Log("popup result:".string(ppr))
    return ppr
endfunction "}}}

fun! XPTemplateStart(pos, ...) " {{{
    let x = g:XPTobject()

    call s:log.Log("a:000".string(a:000))

    if a:0 == 1 &&  type(a:1) == type({}) && has_key( a:1, 'tmplName' )  
        " exact template trigger, without depending on any input

        let startColumn = a:1.startPos[1]
        let templateName = a:1.tmplName

        call cursor(a:1.startPos)

        return  s:DoStart( { 'line' : a:1.startPos[0], 'col' : startColumn, 'matched' : templateName } )

    else 
        " input mode

        let cursorColumn = col(".")

        if x.wrapStartPos
            " TODO store wrapping and normal tempalte separately

            let startLineNr = line(".")
            let startColumn = x.wrapStartPos

        else
            call s:log.Log("x.keyword=" . x.keyword)

            " TODO test escaping
            let [startLineNr, startColumn] = searchpos('\V\%(\w\|'. x.keyword .'\)\+\%#', "bn", line("."))

            if startLineNr == 0
                let [startLineNr, startColumn] = [line("."), col(".")]
            endif

        endif

        let templateName = strpart( getline(startLineNr), startColumn - 1, cursorColumn - startColumn )

    endif
    
    call s:log.Log( 'to popup, templateName='.templateName )

    return s:Popup( templateName, startColumn )

endfunction " }}}

fun! s:ParseIndent(x, p) "{{{
    let x = a:x

    if a:p ==# "auto"
        let x.type = 'auto'


    elseif a:p =~ '/\d\+\(\*\d\+\)\?'
        " TODO deprecated 
        let x.type = 'rate'

        call s:log.Log("a:p=".a:p)
        let str = matchstr(a:p, '/\d\+\(\*\d\+\)\?')

        let x.rate =split(str, '/\|\*')

        if len(x.rate) == 1
            let x.rate[1] = &l:shiftwidth
        endif
    else
        " a:p == 'keep'
        let x.type = 'keep'
    endif

endfunction "}}}

" TODO refine me
fun! s:GetHint(ctx) "{{{

    if has_key(a:ctx, 'hint')
        let a:ctx.hint = s:Eval(a:ctx.hint)
    else
        " Note: empty means nothing, "" means something that can override others
        " let a:ctx.hint = ""
    endif

endfunction "}}}

fun! s:ParsePriorityString(s) "{{{
    let x = g:XPTobject()

    let pstr = a:s
    let prio = 0

    if pstr == ""
        let prio = x.snipFileScope.priority
    else

        let p = matchlist(pstr, '\V\^\(' . s:priPtn . '\)' . '\%(' . '\(\[+-]\)' . '\(\d\+\)\?\)\?\$')

        let base   = 0
        let r      = 1
        let offset = 0

        if p[1] != ""
            if has_key(s:priorities, p[1])
                let base = s:priorities[p[1]]
            elseif p[1] =~ '^\d\+$'
                let base = 0 + p[1]
            else
                let base = 0
            endif
        else
            let base = 0
        endif

        let r = p[2] == '+' ? 1 : (p[2] == '-' ? -1 : 0)

        if p[3] != ""
            let offset = 0 + p[3]
        else
            let offset = 1
        endif

        let prio = base + offset * r

    endif

    call s:log.Log("parse priority : str=".a:s." value=".prio)

    return prio
endfunction "}}}


fun! s:newTemplateRenderContext( xptBufData, tmplName ) "{{{
    if s:getRenderContext().processing
        call s:PushCtx()
    endif

    let renderContext = s:createRenderContext(a:xptBufData)

    let renderContext.phase = 'inited'
    let renderContext.tmpl  = a:xptBufData.normalTemplates[a:tmplName]

    return renderContext
endfunction "}}}

fun! s:DoStart(sess) " {{{
    " @param sess       xpopup call back argument

    let x = g:XPTobject()

    if !has_key( x.normalTemplates, a:sess.matched )
        return g:xpt_post_action
    endif

    let [lineNr, column] = [ a:sess.line, a:sess.col ]
    let cursorColumn = col(".")
    let tmplname = a:sess.matched

    let ctx = s:newTemplateRenderContext( x, tmplname )


    call s:RenderTemplate([ lineNr, column ], [ lineNr, cursorColumn ])


    let ctx.phase = 'rendered'
    let ctx.processing = 1


    if empty(x.stack)
        call s:ApplyMap()
    endif

    let x.wrap = ''
    let x.wrapStartPos = 0

    let action =  s:GotoNextItem()

    call s:log.Debug("post action =".action.g:xpt_post_action)
    call s:log.Debug("mode:".mode())

    call s:log.Debug( "tmpl:", s:TextBetween( XPMpos( ctx.marks.tmpl.start ), XPMpos( ctx.marks.tmpl.end ) ) )

    " NOTE: g:xpt_post_action is for debug only
    return action . g:xpt_post_action

endfunction " }}}

" TODO deal with it in any condition
fun! s:FinishRendering(...) "{{{
    let x = g:XPTobject()
    let renderContext = s:getRenderContext()
    let xp = renderContext.tmpl.ptn

    " call s:log.Log("FinishRendering...........")

    match none

    " let l = line(".")
    " let toEnd = col(".") - len(getline("."))

    " " unescape
    " exe "silent! %snomagic/\\V" .s:TmplRange() . s:unescapeHead . xp.l . '/\1' . xp.l . '/g'
    " exe "silent! %snomagic/\\V" .s:TmplRange() . s:unescapeHead . xp.r . '/\1' . xp.r . '/g'

    " " format template text
    " if &ft =~ s:ftNeedToRedraw
        " redraw
    " endif
    " call s:Format(1)

    " call cursor(l, toEnd + len(getline(l)))

    call s:removeMarksInRenderContext(renderContext)

    if empty(x.stack)
        let renderContext.processing = 0
        let renderContext.phase = 'finished'
        call s:ClearMap()
    else
        call s:PopCtx()
        let renderContext = s:getRenderContext()
        let behavior = renderContext.item.behavior
        if has_key( behavior, 'gotoNextAtOnce' ) && behavior.gotoNextAtOnce
          return s:GotoNextItem()
        endif
    endif

    return ''
endfunction "}}}

fun! s:removeMarksInRenderContext( renderContext ) "{{{

    let renderContext = a:renderContext

    call XPMremoveMarkStartWith( renderContext.markNamePre )
endfunction "}}}

fun! s:Popup(pref, coln) "{{{

    let x = g:XPTobject()


    let cmpl=[]
    let cmpl2 = []
    let dic = x.normalTemplates

    let ctxs = s:SynNameStack(line("."), a:coln)

    call s:log.Log("Popup, pref and coln=".a:pref." ".a:coln)


    let ignoreCase = a:pref !~# '\u'


    for [ key, templateObject ] in items(dic)

        if templateObject.wrapped && empty(x.wrap) || !templateObject.wrapped && !empty(x.wrap)
            continue
        endif

        if has_key(templateObject.setting, "syn") && templateObject.setting.syn != '' && match(ctxs, '\c'.templateObject.setting.syn) == -1
            continue
        endif

        if has_key( templateObject.setting, 'hidden' ) && templateObject.setting.hidden == '1'
            continue
        endif

        let hint = has_key( templateObject.setting, 'hint' ) ? templateObject.setting.hint : ''

        " buildins come last
        if key =~# "^[A-Z]"
            call add(cmpl2, {'word' : key, 'menu' : hint })
        else
            call add(cmpl, {'word' : key, 'menu' : hint})
        endif

    endfor

    call sort(cmpl)
    call sort(cmpl2)
    let cmpl = cmpl + cmpl2


    return XPPopupNew(s:pumCB, {}, cmpl).popup(a:coln)

endfunction "}}}



" TODO use tabstop if expandtab is not set
" TODO bad name, bad arguments
fun! s:ApplyTmplIndent(renderContext, templateText) "{{{
    let renderContext = a:renderContext
    let indent = renderContext.tmpl.setting.indent
    let tmpl = a:templateText

    let baseIndent = repeat(" ", indent("."))
    " at first, only use default indent
    if indent.type =~# 'keep\|rate\|auto'

        if indent.type ==# "rate"
            let patternOfOriginalIndent = repeat(' ', indent.rate[0])
            let patternOfOriginalIndent ='\(\%('.patternOfOriginalIndent.'\)*\)'

            let expandedIndent = repeat('\1', indent.rate[1] / indent.rate[0])

            call s:log.Log("indent:ptn, rep", patternOfOriginalIndent, expandedIndent)

            let tmpl = substitute(tmpl, '\%(^\|\n\)\zs'.patternOfOriginalIndent, expandedIndent, 'g')
        endif

        let tmpl = substitute(tmpl, '\n', '&' . baseIndent, 'g')

    endif

    return tmpl

endfunction "}}}

" TODO do it earlier?
" TODO whether it is necessary to support dynamically generated snippet

let s:oldRepPattern = '\w\*...\w\*'

fun! s:ParseRepetition(str, x) "{{{
    let x = a:x
    let xp = x.renderContext.tmpl.ptn
    let tmplObj = x.renderContext.tmpl

    let tmpl = a:str


    let bef = ""
    let rest = ""
    let rp = xp.lft . s:oldRepPattern . xp.rt
    let repPtn = '\V\(' . rp . '\)\_.\{-}' . '\1'
    let repContPtn = '\V\(' . rp . '\)\zs\_.\{-}' . '\1'


    let stack = []
    let from = 0
    while 1
        let startOfMatch = match(tmpl, repPtn, from)
        if startOfMatch == -1
            break
        endif
        let stack += [startOfMatch]
        let from = startOfMatch + 1
    endwhile


    while stack != []

        let matchpos = stack[-1]
        unlet stack[-1]

        let bef = tmpl[:matchpos-1]
        let rest = tmpl[matchpos : ]

        let indent = s:GetIndentBeforeEdge( tmplObj, bef )

        call s:log.Log( 'bef=' . bef )
        call s:log.Log( 'indent=' . indent )
        let repeatPart = matchstr(rest, repContPtn)
        let repeatPart = 'BuildIfNoChange(' . string( repeatPart ) . ')'
        let repeatPart = s:BuildFilterIndent( repeatPart, indent )
        let symbol = matchstr(rest, rp)
        let name = substitute( symbol, '\V' . xp.lft . '\|' . xp.rt, '', 'g' )
        
        let tmplObj.setting.postFilters[ name ] = repeatPart
        


        let bef .= symbol
        let rest = substitute(rest, repPtn, '', '')
        let tmpl = bef . rest

    endwhile

    call s:log.Log( 'template after parse repetition:', tmpl )
    return tmpl


endfunction "}}}

fun! s:GetIndentBeforeEdge( tmplObj, textBeforeLeftMark )
    let xp = a:tmplObj.ptn

    if a:textBeforeLeftMark =~ '\V' . xp.lft . '\_[^' . xp.r . ']\*\%$'
        call s:log.Debug( 'has edge' )
        let tmpBef = substitute( a:textBeforeLeftMark, '\V' . xp.lft . '\_[^' . xp.r . ']\*\%$', '', '' )
        call s:log.Debug( 'tmpBef=' . tmpBef )
        let indentOfFirstLine = matchstr( tmpBef, '.*\n\zs\s*' )

    else
        let indentOfFirstLine = matchstr( a:textBeforeLeftMark, '.*\n\zs\s*' )
    endif

    return len( indentOfFirstLine )
endfunction


fun! s:parseQuotedPostFilter( tmplObj ) "{{{
    let xp = a:tmplObj.ptn
    let postFilters = a:tmplObj.setting.postFilters
    let quoter = a:tmplObj.setting.postQuoter

    let startPattern = '\V\_.\{-}\zs' . xp.lft . '\_[^' . xp.r . ']\*' . quoter.start . xp.rt
    let endPattern = '\V' . xp.lft . quoter.end . xp.rt

    call s:log.Log( 'parse Quoted Post Filter for ' . a:tmplObj.name )

    call s:log.Log( 'startPattern=' . startPattern )
    call s:log.Log( 'endPattern=' . endPattern )

    let snip = a:tmplObj.tmpl


    " Note: pattern can not satisfy that most prefix and most xp.lft can be
    " found. Thus stack must be used 
    let stack = []

    let startPos = 0
    while startPos != -1
      let startPos = match(snip, startPattern, startPos)
      call s:log.Log( "found:" . startPos )
      
      if startPos != -1
          call add( stack, startPos)
          let startPos += len( matchstr( snip, startPattern, startPos ) )
      endif
    endwhile

    while 1

        if empty( stack )
          break
        endif

        let startPos = remove( stack, -1 )


        let endPos = match( snip, endPattern, startPos + 1 )
        if endPos == -1
            break
        endif

        let startText = matchstr( snip, startPattern, startPos )
        let endText   = matchstr( snip, endPattern, endPos )


        " without left mark, right mark, start quoter
        let name = startText[ 1 : -1 - len( quoter.start ) - 1 ]

        " deal with edge
        if name =~ xp.lft
            let name = matchstr( name, '\V' . xp.lft . '\zs\_.\*' )

            " has right edge ?
            if name =~ xp.lft
                let name = matchstr( name, '\V\_.\*\ze' . xp.lft )
            endif
        endif


        call s:log.Log( 'startText=' . startText )
        call s:log.Log( 'endText=' . endText )
        call s:log.Log( 'name=' . name )


        let plainPostFilter = snip[ startPos + len( startText ) : endPos - 1 ]
        
        let firstLineIndent = s:GetIndentBeforeEdge( a:tmplObj, snip[ : startPos - 1 ] )

        let plainPostFilter = 'BuildIfNoChange(' . string( plainPostFilter ) . ')'
        let plainPostFilter = s:BuildFilterIndent( plainPostFilter, firstLineIndent )

        let postFilters[ name ] = plainPostFilter

        call s:log.Debug( 'name=' . name )
        call s:log.Debug( 'quoted post filter=' . string( postFilters[ name ] ) )
        " right mark, start quoter
        let snip = snip[ : startPos + len( startText ) - 1 - 1 - len( quoter.start ) ] 
                    \. snip[ endPos + len( endText ) - 1 : ]

    endwhile

    return snip

endfunction "}}}



fun! s:RenderTemplate(nameStartPosition, nameEndPosition) " {{{

    call s:log.Debug( 'RenderTemplate : start, end=' . string( [ a:nameStartPosition, a:nameEndPosition ] ) )

    let x = g:XPTobject()
    let ctx = s:getRenderContext()
    let xp = s:getRenderContext().tmpl.ptn

    let ctx.phase = 'rendering'

    let tmpl = ctx.tmpl.tmpl

    if type(tmpl) == type(function("tr"))
        let tmpl = tmpl()
    else
        let tmpl = tmpl
    endif

    if tmpl =~ '\n'
        let tmpl = s:ApplyTmplIndent(ctx, tmpl)
    endif
    let tmpl = s:ParseRepetition(tmpl, x)

    " Note: simple implementation of wrapping, the better way is by default value
    " TODO use default value!
    let wrapPos = match( tmpl, xp.lft . s:wrappedName . xp.rt )
    if wrapPos != -1
        let indent = matchstr( tmpl[ : wrapPos - 1 ], '\V\.\*\%(\^\|\n\)\zs\s\*' )
        let wrapped = substitute( x.wrap, '\n', "\n" . indent, 'g' )
        let tmpl = substitute(tmpl, '\V' . xp.lft . s:wrappedName . xp.rt, wrapped, 'g')
    endif



    " update xpm status
    call XPMupdate()
    call s:log.Debug( 'before insert new template mark' )
    call s:log.Debug( XPMallMark() )
    

    call XPMadd( ctx.marks.tmpl.start, a:nameStartPosition, g:XPMpreferLeft )
    call XPMadd( ctx.marks.tmpl.end, a:nameEndPosition, g:XPMpreferRight )

    
    call XPMsetLikelyBetween( ctx.marks.tmpl.start, ctx.marks.tmpl.end )
    call XPreplace( a:nameStartPosition, a:nameEndPosition, tmpl )

    call s:log.Debug( 'after insert new template' )
    call s:log.Debug( XPMallMark() )

    call s:log.Log( "template start and end=" . string( [ XPMpos( ctx.marks.tmpl.start ), XPMpos( ctx.marks.tmpl.end )] ) )


    " initialize lists
    let ctx.firstList = []
    let ctx.itemList = []
    let ctx.lastList = []


    if 0 != s:BuildPlaceHolders( ctx.marks.tmpl )
        return s:Crash()
    endif

    call s:log.Log("after buildvalues tmpl=\n", s:TextBetween(s:TL(), s:BR()))



    " open all folds
    call s:TopTmplRange()
    silent! normal! gvzO



endfunction " }}}

" [ first, second, third, right-mark ]
" [ first, first, right-mark, right-mark ]
fun! s:GetNameInfo(end) "{{{
    let x = g:XPTobject()
    let xp = x.renderContext.tmpl.ptn

    if getline(".")[col(".") - 1] != xp.l
        throw "cursor is not at item start position:".string(getpos(".")[1:2])
    endif

    call s:log.Log("GetNameInfo from".string(getpos(".")[1:2]))
    call s:log.Log("to:".string(a:end))
    call s:log.Debug( 'pattner:' . string( [ xp.lft, xp.rt ] ) )

    let endn = a:end[0] * 10000 + a:end[1]

    let l0 = getpos(".")[1:2]
    let r0 = searchpos(xp.rt, 'nW')

    let r0n = r0[0] * 10000 + r0[1]

    if r0 == [0, 0] || r0n >= endn
        " no item exists
        return [[0, 0], [0, 0], [0, 0], [0, 0]]
    endif

    let l1 = searchpos(xp.lft, 'W')
    let l2 = searchpos(xp.lft, 'W')

    let l1n = l1[0] * 10000 + l1[1]
    let l2n = l2[0] * 10000 + l2[1]

    if l1n > r0n || l1n >= endn
        let l1 = [0, 0]
    endif
    if l2n > r0n || l1n >= endn
        let l2 = [0, 0]
    endif

    if l1 != [0, 0] && l2 != [0, 0]
        " 2 edges
        return [l0, l1, l2, r0]
    elseif l1 == [0, 0] && l2 == [0, 0]
        " no edge
        return [l0, l0, r0, r0]
    else
        " only left edge
        return [l0, l1, r0, r0]
    endif

endfunction "}}}

fun! s:GetValueInfo(end) "{{{
    let x = g:XPTobject()
    let xp = x.renderContext.tmpl.ptn

    if getline(".")[col(".") - 1] != xp.r
        throw "cursor is not at item end position:".string(getpos(".")[1:2])
    endif

    let nEnd = a:end[0] * 10000 + a:end[1]

    let r0 = [ line( "." ), col( "." ) ]

    let l0 = searchpos(xp.lft, 'nW', a:end[0])
    if l0 == [0, 0]
        let l0n = nEnd
    else
        let l0n = min([l0[0] * 10000 + l0[1], nEnd])
    endif

    call s:log.Log("GetValueInfo:end limit=" . l0n)

    let r1 = searchpos(xp.rt, 'W', a:end[0])
    if r1 == [0, 0] || r1[0] * 10000 + r1[1] > l0n
        return [r0, copy(r0), copy(r0)]
    endif

    let r2 = searchpos(xp.rt, 'W', a:end[0])
    if r2 == [0, 0] || r2[0] * 10000 + r2[1] > l0n
        return [r0, r1, copy(r1)]
    endif

    return [r0, r1, r2]
endfunction "}}}

fun! s:BuildFilterIndent( str, firstLineIndent ) "{{{
    let min = a:firstLineIndent

    " protect the first and last line break
    let list = split( a:str, "\n", 1 )

    " from the 2nd line, to the last 2nd line
    for line in list[ 1 : ]

        let indentWidth = len( matchstr( line, '^\s*' ) )

        call s:log.Log("indent width:".indentWidth." line=".line)
        let min = min( [ min, indentWidth ] )
    endfor

    call s:log.Debug( 'build indent for ' . a:str )

    call s:log.Log("minimal indent:".min)

    " *) The minimal indent at start of line is removed
    " *) The indent of the line filter start is also recorded.
    "   Thus relative indent is recorded.
    let pattern = '\n\s\{' . min . '}'

    call s:log.Debug( 'firstLineIndent=' . a:firstLineIndent )

    return repeat( ' ', a:firstLineIndent - min ) . "\n" . substitute( a:str, pattern, "\n", 'g' )
endfunction "}}}

" XSET name|def=
" XSET name|post=
"
" `name^ per-item post-filter ^^


fun! s:CreatePlaceHolder( ctx, nameInfo, valueInfo ) "{{{

    " 1) Place holder with edge is the editable place holder, for edges of
    " uneditable place holder being ignored. So that only place holder is
    " edited can has edges that will take effect.
    "
    " 2) If none of place holders of one item has edge. The first place
    " holder will be the editable one.
    "
    " 3) if more than one place holders set with edge, the first
    " encountered one takes effect.

    let xp = a:ctx.tmpl.ptn


    " 1 is length of left mark 
    let leftEdge  = s:TextBetween(a:nameInfo[0], a:nameInfo[1])
    let name      = s:TextBetween(a:nameInfo[1], a:nameInfo[2])
    let rightEdge = s:TextBetween(a:nameInfo[2], a:nameInfo[3])

    let [ leftEdge, name, rightEdge ] = [ leftEdge[1 : ], name[1 : ], rightEdge[1 : ] ]

    let fullname  = leftEdge . name . rightEdge

    call s:log.Log( "item is :" . string( [ leftEdge, name, rightEdge ] ) )


    " TODO quoted pattern
    if fullname =~ '\V' . xp.item_var . '\|' . xp.item_func
        " that is only a instant place holder
        return { 'value' : fullname }
    endif

    " PlaceHolder.item is set by caller.
    " At this step, to which item this placeHolder belongs is not concerned.
    let placeHolder = { 
                \ 'name'        : name, 
                \ 'isKey'       : (a:nameInfo[0] != a:nameInfo[1]), 
                \ 'ontimeFilter': '', 
                \ 'postFilter'  : '', 
                \ }


    if placeHolder.isKey
        call extend( placeHolder, {
                    \     'leftEdge'  : leftEdge,
                    \     'rightEdge' : rightEdge,
                    \     'fullname'  : fullname,
                    \ }, 'force' )
    endif

    " TODO support of group post filter and ph post filter
    if a:valueInfo[1] != a:valueInfo[0]
        let isPostFilter = a:valueInfo[1][0] == a:valueInfo[2][0] 
                    \&& a:valueInfo[1][1] + 1 == a:valueInfo[2][1]

        let val = s:TextBetween( a:valueInfo[0], a:valueInfo[1] )
        let val = val[1:]
        let val = g:xptutil.UnescapeChar( val, xp.l . xp.r )
        let val = s:BuildFilterIndent( val, indent( a:valueInfo[0][0] ) )


        if isPostFilter
            let placeHolder.postFilter = val
        else
            let placeHolder.ontimeFilter = val
        endif

        call s:log.Debug("placeHolder post filter:key=val : " . name . "=" . val)
    endif

    return placeHolder

endfunction "}}}


" fun! g:xptutil.UnescapeChar( str, chars )
    " " unescape only chars started with several '\' 
" 
    " " remove all '\'.
    " let chars = substitute( a:chars, '\\', '', 'g' )
" 
    " 
    " let pattern = s:unescapeHead . '\(\[' . escape( chars, '\]' ) . ']\)'
    " call s:log.Log( 'to unescape pattern='.pattern )
    " let unescaped = substitute( a:str, pattern, '\1\2', 'g' )
    " call s:log.Log( 'unescaped ='.unescaped )
    " return unescaped
" endfunction



" TODO move me to where I should be
" mark naming principle:
"   XPTM{ nested_level }_{ name }
"   nested_level starts from 0
"   name can be : 
"       `tmpl`start
"       `tmpl`end
"       itemname`placeholder_index`{start|end}
"       itemname`key`{start|end}
"       ``anonymous_index`{start|end}
" Using XPT-left mark as segments delimiter, for no left-mark can be used in
" itemname
"

let s:anonymouseIndex = 0

fun! s:buildMarksOfPlaceHolder(ctx, item, placeHolder, nameInfo, valueInfo) "{{{
    " TODO do not create edge mark if not necessary 

    let [ctx, item, placeHolder, nameInfo, valueInfo] = 
                \ [a:ctx, a:item, a:placeHolder, a:nameInfo, a:valueInfo]

    if item.name == ''
        let markName =  '``' . s:anonymouseIndex
        let s:anonymouseIndex += 1

    else
        let markName =  item.name . s:buildingSeqNr . '`' . ( placeHolder.isKey ? 'key' : (len(item.placeHolders)-1) )

    endif
    " TODO maybe using the mark-symbol variable is better?
    let markPre = ctx.markNamePre . markName . '`'

    call extend( placeHolder, {
                \ 'mark'     : {
                \       'start' : markPre . 'start', 
                \       'end'   : markPre . 'end', 
                \   }, 
                \}, 'force' )

    if placeHolder.isKey
        call extend( placeHolder, {
                    \     'editMark'  : {
                    \           'start' : markPre . 'eStart', 
                    \           'end'   : markPre . 'eEnd', 
                    \       }, 
                    \}, 'force' )
    endif


    " move to after the last right mark
    let valueInfo[2][1] += 1

    " Adjust position of nameInfo and valueInfo.
    " If 2 positions are at the same line, increase shifting width by 1.
    if placeHolder.isKey
        let shift = ( nameInfo[0] != nameInfo[1] && nameInfo[0][0] == nameInfo[1][0])
        let nameInfo[1][1] -= shift
        call s:log.Debug( 'nameInfo.1 decr=' . shift )

        let shift = (nameInfo[1][0] == nameInfo[2][0]) * (shift + 1)
        let nameInfo[2][1] -= shift
        call s:log.Debug( 'nameInfo.2 decr=' . shift )

        if nameInfo[2] != nameInfo[3]
            let shift = (nameInfo[2][0] == nameInfo[3][0]) * (shift + 1)
            let nameInfo[3][1] -= shift
            call s:log.Debug( 'nameInfo.3 decr=' . shift )
        endif

        call XPreplace(nameInfo[0], valueInfo[2], placeHolder.fullname)

    elseif nameInfo[0][0] == nameInfo[3][0]
        let nameInfo[3][1] -= 1
        call XPreplace(nameInfo[0], valueInfo[2], placeHolder.name)

    endif




    " must add marks in fixed order

    call XPMadd( placeHolder.mark.start, nameInfo[0], 'l' )

    " TODO remember to remove editMark
    if placeHolder.isKey
        call XPMadd( placeHolder.editMark.start, nameInfo[1], 'l' )
        call XPMadd( placeHolder.editMark.end,   nameInfo[2], 'r' )
    endif

    call XPMadd( placeHolder.mark.end,   nameInfo[3], 'r' )

endfunction "}}}

fun! s:addItemToRenderContext( ctx, item ) "{{{

    let [ctx, item] = [ a:ctx, a:item ]

    if item.name != ''
        let ctx.itemDict[ item.name ] = item
    endif

    " TODO precise phase, do not use false condition
    if ctx.phase != 'rendering'
        " fillin phase 
        " call insert( ctx.itemList, item, 0 )
        call add( ctx.firstList, item )

        call s:log.Log( 'item insert to the head of itemList:' . string( item ) )
        return

    endif

    " rendering phase 

    let firstDict = ctx.tmpl.setting.firstDict
    let lastDict  = ctx.tmpl.setting.lastDict

    if item.name == ''
        call add( ctx.itemList, item )

    elseif has_key( firstDict, item.name )

        let ctx.firstList[ firstDict[ item.name ] ] = item
        call s:log.Log( item.name . ' added to firstList' . string( ctx.firstList ) )
        call s:log.Debug( 'index:' . firstDict[ item.name ] )

    elseif has_key( lastDict, item.name )
        let ctx.lastList[ lastDict[ item.name ] ] = item
        call s:log.Log( item.name . ' added to lastList :' . string( ctx.lastList ) )
        call s:log.Debug( 'index:' . lastDict[ item.name ] )

    else
        call add( ctx.itemList, item )
        call s:log.Log( item.name . ' added to itemList' )

    endif


endfunction "}}}

fun! s:BuildPlaceHolders( markRange ) "{{{

    let s:buildingSeqNr += 1

    let renderContext = s:getRenderContext()
    let tmplObj = renderContext.tmpl
    let xp = renderContext.tmpl.ptn


    let [ start, end ] = XPMposList( a:markRange.start, a:markRange.end )
    let content = s:TextBetween( start, end )
    let contentUnescpaed = g:xptutil.UnescapeChar( content, xp.l . xp.r )

    if content !=# contentUnescpaed

        call XPRstartSession()
        call XPreplaceByMarkInternal( a:markRange.start, a:markRange.end, contentUnescpaed )
        call XPRendSession()
    endif


    let renderContext.action = 'build'

    if renderContext.firstList == []
        let renderContext.firstList = copy(renderContext.tmpl.setting.firstListSkeleton)
    endif
    if renderContext.lastList == []
        let renderContext.lastList = copy(renderContext.tmpl.setting.lastListSkeleton)
    endif

    let renderContext.buildingMarkRange = copy( a:markRange )


    let start = XPMpos( a:markRange.start )
    call cursor( start )



    let i = 0
    while i < 10000
        let i += 1

        call s:log.Log( "build from here" )


        let end = XPMpos( a:markRange.end )
        let nEnd = end[0] * 10000 + end[1]

        call s:log.Log("build place holders : end=".string(end))


        " TODO move this action to GetNameInfo
        let nn = searchpos(xp.lft, 'cW')
        if nn == [0, 0] || nn[0] * 10000 + nn[1] >= nEnd
            break
        endif

        let nameInfo = s:GetNameInfo(end)
        if nameInfo[0] == [0, 0]
            " no more items 
            break
        endif


        " locate at end of place holder
        call cursor(nameInfo[3])


        let valueInfo = s:GetValueInfo(end)
        if valueInfo[0] == [0, 0]
            " there is no right mark matching the left mark
            break
        endif


        call s:log.Log("got nameinfo, valueinfo:".string([nameInfo, valueInfo]))


        let placeHolder = s:CreatePlaceHolder(renderContext, nameInfo, valueInfo)

        call s:log.Log( 'built placeHolder=' . string( placeHolder ) )

        if has_key( placeHolder, 'value' )
            " render it instantly
            call s:log.Debug( 'instant placeHolder' )

            " TODO save this 'value' variable?
            let value = s:Eval( placeHolder.value )
            if value == "\n"
                " simple format, without indent setting 

                let indentSpace = repeat( ' ', indent( nameInfo[0][0] ) )
                let value = substitute( value, '\n', '&' . indentSpace, 'g' )
            elseif value !~ '\n'
                " simple format, without indent setting 
                
            else
                " with indent setting 
                let [ filterIndent, filterText ] = s:GetFilterIndentAndText( value )
                let value = s:AdjustIndentAccordingToLine( filterText, filterIndent, nameInfo[0][0] )
                call s:log.Log( "instant value with indent setting:" . string( value ) )
            endif

            let valueInfo[-1][1] += 1
            call XPreplace( nameInfo[0], valueInfo[-1], value )

            " Cursor left just after replacement, and it is where next search
            " start

        else
            " build item and marks, as a fillin place holder

            let item = s:BuildItemForPlaceHolder( renderContext, placeHolder )

            call s:buildMarksOfPlaceHolder( renderContext, item, placeHolder, nameInfo, valueInfo )

            " nameInfo and valueInfo is updated according to new position
            " call cursor(nameInfo[3])

            call s:log.Debug( 'built ph='.string( placeHolder ) )

            call s:ApplyPreValues( placeHolder )


            call cursor( XPMpos( placeHolder.mark.end ) )

        endif

    endwhile

    call filter( renderContext.firstList, 'v:val != {}' )
    call filter( renderContext.lastList, 'v:val != {}' )

    let renderContext.itemList = renderContext.firstList + renderContext.itemList + renderContext.lastList

    let renderContext.firstList = []
    let renderContext.lastList = []
    call s:log.Log( "itemList:" . String( renderContext.itemList ) )

    let end = XPMpos( a:markRange.end )

    call cursor( end )

    let renderContext.action = ''
    return 0
endfunction "}}}

" TODO simplify : if PH has preValue, replace it at once, without replacing with the name
fun! s:ApplyPreValues( placeHolder )
    let renderContext = s:getRenderContext()
    let tmplObj = renderContext.tmpl
    let xp = tmplObj.ptn
    let setting = tmplObj.setting

    let preValue = a:placeHolder.name == '' ? '' : 
                \ (has_key( setting.preValues, a:placeHolder.name ) ? setting.preValues[ a:placeHolder.name ] : '')

    if !s:IsFilterEmpty( preValue ) 
        let [ filterIndent, filterText ] = s:GetFilterIndentAndText( preValue )
        call s:SetPreValue( a:placeHolder, filterIndent, filterText )

    else
        let preValue = has_key( setting.defaultValues, a:placeHolder.name ) ? 
                    \setting.defaultValues[ a:placeHolder.name ] 
                    \: a:placeHolder.ontimeFilter

        if !s:IsFilterEmpty( preValue ) 
            let [ filterIndent, filterText ] = s:GetFilterIndentAndText( preValue )
            if filterText !~ '\V' . xp.item_func . '\|' . xp.item_qfunc 
                call s:SetPreValue( a:placeHolder, filterIndent, filterText )
            endif
        endif

    endif
endfunction


fun! s:SetPreValue( placeHolder, indent, text )
    let text = s:Eval( a:text )

    let marks = a:placeHolder.isKey ? a:placeHolder.editMark : a:placeHolder.mark
    let text = s:AdjustIndentAccordingToLine( text, a:indent, XPMpos( marks.start )[0] )
    call XPRstartSession()
    call XPreplaceByMarkInternal( marks.start, marks.end, text )
    call XPRendSession()
endfunction



fun! s:BuildItemForPlaceHolder( ctx, placeHolder ) "{{{
    " anonymous item with name set to '' will never been added to a:ctx.itemDict

    if has_key(a:ctx.itemDict, a:placeHolder.name)
        let item = a:ctx.itemDict[ a:placeHolder.name ]

    else
        let item = { 'name'         : a:placeHolder.name, 
                    \'fullname'     : a:placeHolder.name, 
                    \'placeHolders' : [], 
                    \'keyPH'        : s:NullDict, 
                    \'behavior'     : {}, 
                    \}

        call s:addItemToRenderContext( a:ctx, item )

    endif



    if a:placeHolder.isKey
        let item.keyPH = a:placeHolder
        let item.fullname = a:placeHolder.fullname
    else
        call add( item.placeHolders, a:placeHolder )
    endif

    call s:log.Log( 'item built=' . string( item ) )

    return item
endfunction "}}}


fun! s:GetStaticRange(p, q) "{{{
    let tl = a:p
    let br = a:q


    let r = ''
    if tl[0] == br[0]
        let r = r . '\%' . tl[0] . 'l'
        if tl[1] > 1
            let r = r . '\%>' . (tl[1]-1) .'c'
        endif

        let r = r . '\%<' . br[1] . 'c'
    else
        let r = r . '\%>' . tl[0] .'l' . '\%<' . br[0] . 'l'
        let r = r
                    \. '\|' .'\%('.'\%'.tl[0].'l\%>'.(tl[1]-1) .'c\)'
                    \. '\|' .'\%('.'\%'.br[0].'l\%<'.(br[1]+0) .'c\)'
    endif

    let r = '\%(' . r . '\)'
    return '\V'.r

endfunction "}}}

" TODO use syn-keyword
fun! s:HighLightItem(name, switchon) " {{{
    let xp = s:getRenderContext().tmpl.ptn
    if a:switchon
        let ptn = substitute(xp.itemContentPattern, "NAME", a:name, "")

        let ptn = xp.itemMarkLPattern
        exe "2match XPTIgnoredMark /". ptn ."/"

        let ptn = xp.itemMarkRPattern
        exe "3match XPTIgnoredMark /". ptn ."/"
    else
        exe "2match none"
        exe "3match none"
    endif
endfunction " }}}

fun! s:TopTmplRange() "{{{
    let x = g:XPTobject()
    if empty(x.stack)
        return s:TmplRange()
    else
        let old = x.renderContext
        let x.renderContext = x.stack[0]
        let r = s:TmplRange()
        let x.renderContext = old
    endif
    return r
endfunction "}}}

fun! s:TmplRange() "{{{
    let x = g:XPTobject()
    let p = [line("."), col(".")]

    call s:GetRangeBetween(s:TL(), s:BR())

    call cursor(p)
    return s:vrange
endfunction "}}}

fun! s:XPTvisual() "{{{
    if &l:slm =~ 'cmd'
	normal! v\<C-g>
    else
	normal! v
    endif
endfunction "}}}

fun! s:GetRangeBetween(p1, p2, ...) "{{{
    let pre = a:0 == 1 && a:1

    if pre
        let p = getpos(".")[1:2]
    endif

    if a:p1[0]*1000+a:p1[1] <= a:p2[0]*1000+a:p2[1]
        let [p1, p2] = [a:p1, a:p2]
    else
        let [p1, p2] = [a:p2, a:p1]
    endif

    " TODO &selection == 'old'
    if &selection == "inclusive"
        let p2 = s:LeftPos(p2)
    endif

    call cursor(p1)
    call s:XPTvisual()
    call cursor(p2)
    normal! v


    if pre
        call cursor(p)
    endif

    return s:vrange

endfunction "}}}

fun! s:finishCurrentAndGotoNextItem(action) " {{{
    let renderContext = s:getRenderContext()
    let marks = renderContext.leadingPlaceHolder.mark

    " if typing and <tab> pressed together, no update called
    " TODO do not call this if no need to update
    let rc = s:XPTupdate()
    if rc == -1
        " crashed
        return ''
    endif



    " let p = [line("."), col(".")]
    let name = renderContext.item.name

    " call s:HighLightItem(name, 0)

    call s:log.Log("finishCurrentAndGotoNextItem action:" . a:action)

    if a:action ==# 'clear'
        call s:log.Log( 'to clear:' . string( [ XPMpos( marks.start ),XPMpos( marks.end ) ] ) )
        call XPreplace(XPMpos( marks.start ),XPMpos( marks.end ), '')
    endif

    let post = s:ApplyPostFilter()

    let renderContext.step += [{ 'name' : renderContext.item.name, 'value' : post }]
    if renderContext.item.name != ''
        let renderContext.namedStep[renderContext.item.name] = post
    endif

    
    call s:removeCurrentMarks()


    return s:GotoNextItem()

endfunction " }}}

fun! s:removeCurrentMarks()
    let renderContext = s:getRenderContext()
    let item = renderContext.item
    let leader = renderContext.leadingPlaceHolder

    " TODO using XPMremoveMarkStartWith
    call XPMremove( leader.mark.start )
    call XPMremove( leader.mark.end )
    if leader.isKey
        call XPMremove( leader.editMark.start )
        call XPMremove( leader.editMark.end )
    endif

    for ph in item.placeHolders
        call XPMremove( ph.mark.start )
        call XPMremove( ph.mark.end )
    endfor
endfunction

fun! s:RemovePlaceHolderMark( placeHolder )
    call XPMremove( a:placeHolder.mark.start )
    call XPMremove( a:placeHolder.mark.end )

    if a:placeHolder.isKey
        call XPMremove( a:placeHolder.editMark.start )
        call XPMremove( a:placeHolder.editMark.end )
    endif
endfunction

fun! s:ApplyPostFilter() "{{{

    " *) Apply Group-scope post filter to leading place holder.
    " *) Following place holders are updated by trying filter on the following
    " order: ph.postFilter, or ontime filter, of the group-scope post filter.
    " 
    " Thus, some place holder may be filtered twice.
    "

    let renderContext = s:getRenderContext()

    let xp     = renderContext.tmpl.ptn
    let posts  = renderContext.tmpl.setting.postFilters
    let name   = renderContext.item.name
    let leader = renderContext.leadingPlaceHolder
    let marks  = renderContext.leadingPlaceHolder.mark

    let renderContext.phase = 'post'

    let typed = s:TextBetween(XPMpos( marks.start ), XPMpos( marks.end ))


    call s:log.Log("before post filtering, tmpl:\n" . s:TextBetween(XPMpos(renderContext.marks.tmpl.start), XPMpos(renderContext.marks.tmpl.end)))




    if has_key(posts, name)
        let groupPostFilter = posts[ name ]
    else
        let groupPostFilter = ''
    endif

    let leaderPostFilter = leader.postFilter

    if groupPostFilter != ''
        let filter = groupPostFilter
    else
        let filter = leaderPostFilter
    endif

    let filterIndent = matchstr( filter, '\s*\ze\n' )
    let filterText = matchstr( filter, '\n\zs\_.*' )


    call s:log.Log("name:".name)
    call s:log.Log("typed:".typed)
    call s:log.Log('group post filter :' . groupPostFilter)
    call s:log.Log('leader post filter :' . leaderPostFilter)
    call s:log.Log('post filterIndent :' . filterIndent)
    call s:log.Log('post filterText :' . filterText)


    " TODO per-place-holder filter
    " check by 'groupPostFilter' is ok
    if filterText != ''

        let [ text, ifToBuild, rc ] = s:EvalPostFilter( filterText, typed )

        call s:log.Log("before replace, tmpl=\n".s:TextBetween(s:TL(), s:BR()))



        let [ start, end ] = XPMposList( marks.start, marks.end )

        let snip = s:AdjustIndentAccordingToLine( text, filterIndent, start[0] )
        call XPMsetLikelyBetween( marks.start, marks.end )
        call XPreplace(start, end, snip)


        if ifToBuild
            call cursor( start )
            let renderContext.firstList = []
            if 0 != s:BuildPlaceHolders( marks )
                return s:Crash()
            endif

            " change back the phase
            let renderContext.phase = 'post'
        endif

        " call s:RemovePlaceHolderMark( leader )

    endif

    " after indent segment, there is something
    if s:IsFilterEmpty( groupPostFilter )
        call s:UpdateFollowingPlaceHoldersWith( typed, {} )
        return typed
    else
        call s:UpdateFollowingPlaceHoldersWith( typed, { 'indent' : filterIndent, 'post' : text } )
        return text
    endif



    " TODO is this needed?
    " call s:XPTupdate()


endfunction "}}}

fun! s:EvalPostFilter( filter, typed ) "{{{
    let renderContext = s:getRenderContext()

    let post = s:Eval(a:filter, {'typed' : a:typed})

    call s:log.Log("post:\n", string(post))

    if type( post ) == 4
        " dictionary, it is an action object
        if post.action == 'build'
            let res = [ post.text, 1, 0 ]

            " TODO 
        " elseif post.action == 'expandTmpl'
            " let leader = renderContext.leadingPlaceHolder
            " let marks = leader.marks
            " let [ start, end ] = XPMposList( marks.start, marks.end )
" 
            " call XPreplace( start, end, '')
            " return XPTemplateStart(0, {'startPos' : start, 'tmplName' : post.tmplName})
" 
            " let res = [ post. ]
        else
            " unknown action
            let res = [ post.text, 0, 0 ]
        endif

    elseif type( post ) == 1
        " string
        let res = [ post, 1, 0 ]

    else
        " unknown type 
        let res = [ string( post ), 0, 0 ]

    endif

    return res
endfunction "}}}

fun! s:AdjustIndentAccordingToLine( snip, indent, lineNr ) "{{{
    let indent = indent( a:lineNr )
    call s:log.Debug( 'line to get indent:' . getline( a:lineNr ) )
    call s:log.Debug( 'post filter indent at line[' . a:lineNr . ']:' . indent )

    let indentspaces = repeat(' ', indent)

    " remove original indent
    if len( indentspaces ) > len( a:indent )
      let indentspaces = substitute( indentspaces, a:indent, '', '' )
    else
      let indentspaces = ''
    endif

    return substitute( a:snip, "\n", "\n" . indentspaces, 'g' )

endfunction "}}}


" TODO rename me
fun! s:GotoNextItem() "{{{
    " @return   insert mode typing action
    " @param    position from where to start search.

    let renderContext = s:getRenderContext()

    call s:log.Log( 'renderContext=' . string( renderContext ) )

    let placeHolder = s:ExtractOneItem()


    if placeHolder == s:NullDict
        call cursor( XPMpos( renderContext.marks.tmpl.end ) )
        return s:FinishRendering(1)
    endif

    call s:log.Log("ExtractOneItem:".string(placeHolder))
    call s:log.Log("leadingPlaceHolder pos:".string(XPMpos( placeHolder.mark.start )))

    let phPos = XPMpos( placeHolder.mark.start )
    if phPos == [0, 0]
        " error found no position of mark
        call s:log.Error( 'failed to find position of mark:' . placeHolder.mark.start )
        return s:Crash()
    endif

    call s:log.Log( "all marks:" . XPMallMark() )


    let leader =  renderContext.leadingPlaceHolder
    let leaderMark = leader.isKey ? leader.editMark : leader.mark
    call XPMsetLikelyBetween( leaderMark.start, leaderMark.end )

    let postaction = s:InitItem()


    " InitItem may change template stack
    let renderContext = s:getRenderContext()
    let leader =  renderContext.leadingPlaceHolder



    call s:log.Log( 'after InitItem, postaction='.postaction )

    if !renderContext.processing
        return postaction
    endif

    call XPMsetLikelyBetween( leader.mark.start, leader.mark.end )


    if postaction != ''
        return postaction

    else
        if renderContext.leadingPlaceHolder.isKey
            call cursor( XPMpos( renderContext.leadingPlaceHolder.editMark.end ) )
        else
            call cursor( XPMpos( renderContext.leadingPlaceHolder.mark.end ) )
        endif
        return ""

    endif

endfunction "}}}

" fun! s:Format(range) "{{{
" 
    " " TODO 
    " return
" 
" 
" 
    " let x = g:XPTobject()
    " let ctx = x.renderContext
" 
    " if ctx.tmpl.indent.type !=# "auto"
        " return
    " endif
" 
    " call s:PushBackPos()
" 
    " let pt = s:TL()
    " let pt[1] = pt[1] - len(getline(pt[0]))
" 
" 
" 
" 
    " if ctx.processing && ctx.pos.curpos != {}
        " let pi = ctx.pos.editpos.start.pos
        " let pi[1] = pi[1] - len(getline(pi[0]))
" 
        " let pc = s:CTL(x)
        " let pc[1] = pc[1] - len(getline(pc[0]))
        " " let bf = matchstr(x.renderContext.lastBefore, s:stripPtn)
    " endif
" 
    " if a:range == 1
        " call s:log.Log("template before last format:", s:TextBetween(s:TL(), s:BR()))
        " call s:log.Log("template range : ".string([s:TL(), s:BR()]))
        " " call s:log.Log("current syntax:".string(SynNameStack(3, 1)))
        " call s:TmplRange()
        " normal! gv=
    " elseif a:range == 2
        " call s:TopTmplRange()
        " normal! gv=
    " else
        " normal! ==
    " endif
    " call s:log.Log("template after last format:", s:TextBetween(s:TL(), s:BR()))
" 
" 
    " if ctx.processing && ctx.pos.curpos != {}
        " call ctx.pos.editpos.start.set( pi[0], max([pi[1] + len(getline(pi[0])), 1]))
        " " let x.renderContext.pos.curpos.l = max([pc[1] + len(getline(pc[0])), 1])
        " " let x.renderContext.lastBefore = matchstr(getline(pc[0]), '\V\^\s\*'.escape(bf, '\'))
        " " call s:log.Log("bf is:" . bf)
        " call s:log.Log("current line:".getline(pc[0]))
        " " call s:log.Log("lastBefore after format:".x.renderContext.lastBefore)
    " endif
" 
" 
    " call s:PopBackPos()
    " " call cursor(p[0], p[1] + len(getline(".")))
" 
" endfunction "}}}

fun! s:TL(...)
    return XPMpos( g:XPTobject().renderContext.marks.tmpl.start )
endfunction

fun! s:BR(...)
    return XPMpos( g:XPTobject().renderContext.marks.tmpl.end )
endfunction

fun! s:ExtractOneItem() "{{{

    let renderContext = s:getRenderContext()
    let itemList = renderContext.itemList

    let [ renderContext.item, renderContext.leadingPlaceHolder ] = [ {}, {} ]

    if empty( itemList )
        return s:NullDict
    endif

    let item = itemList[ 0 ]

    let renderContext.itemList = renderContext.itemList[ 1 : ]
    if item.name != ''
        unlet renderContext.itemDict[ item.name ]
    endif

    let renderContext.item = item
    
    if empty( item.placeHolders ) && item.keyPH == s:NullDict
        echoerr "item without placeholders!"
        return s:NullDict
    endif


    " TODO when update, avoid updating leadingPlaceHolder
    if item.keyPH == s:NullDict
        let renderContext.leadingPlaceHolder = item.placeHolders[0]
        let item.placeHolders = item.placeHolders[1:]
    else
        let renderContext.leadingPlaceHolder = item.keyPH

    endif

    return renderContext.leadingPlaceHolder

endfunction "}}}

fun! s:HandleDefaultValueAction( ctx, act ) "{{{
    " @return   string  typing 
    "           -1      if this action can not be handled

    let ctx = a:ctx

    if has_key(a:act, 'action') " actions

        call s:log.Log( "type is ".type(a:act). ' {} type is '.type({}) )

        if a:act.action ==# 'expandTmpl' && has_key( a:act, 'tmplName' )
            let ctx.item.behavior.gotoNextAtOnce = 1


            " do NOT need to update position 
            let marks = ctx.leadingPlaceHolder.mark
            call XPreplace(XPMpos( marks.start ), XPMpos( marks.end ), '')
            " call XPMremove( marks.start )
            " call XPMremove( marks.end )
            call XPMsetLikelyBetween( marks.start, marks.end )
            return XPTemplateStart(0, {'startPos' : getpos(".")[1:2], 'tmplName' : a:act.tmplName})

        elseif a:act.action ==# 'finishTemplate'
            " do NOT need to update position 
            call XPreplace(XPMpos( ctx.leadingPlaceHolder.mark.start ), XPMpos( ctx.leadingPlaceHolder.mark.end )
                        \, has_key( a:act, 'postTyping' ) ? a:act.postTyping : '' )

            let xptObj = g:XPTobject() 

            if empty( xptObj.stack )
                return s:FinishRendering()
            else
                " TODO for cursor item in nested template, this is ok. what if
                " need to select something or doing something else?
                return ''
            endif

        elseif a:act.action ==# 'embed'
            " embed a piece of snippet

            return s:EmbedSnippetInLeadingPlaceHolder( ctx, a:act.snippet )

        elseif a:act.action ==# 'next'
            " goto next 

            let text = has_key( a:act, 'text' ) ? a:act.text : ''
            call s:FillinLeadingPlaceHolderAndSelect( ctx, text )

            return s:finishCurrentAndGotoNextItem( '' )


        else " other action

        endif

        return -1

    else
        return -1
    endif

endfunction "}}}

fun! s:EmbedSnippetInLeadingPlaceHolder( ctx, snippet ) "{{{
    " TODO remove needless marks
    let ph = a:ctx.leadingPlaceHolder
    
    let marks = ph.isKey ? ph.editMark : ph.mark
    let range = [ XPMpos( marks.start ), XPMpos( marks.end ) ]
    if range[0] == [0, 0] || range[1] == [0, 0]
        return s:Crash( 'leading place holder''s mark lost:' . string( marks ) )
    endif

    call XPreplace( range[0], range[1] , a:snippet )

    if 0 != s:BuildPlaceHolders( marks )
        return s:Crash('building place holder failed')
    endif

    return s:GotoNextItem()
endfunction "}}}

fun! s:FillinLeadingPlaceHolderAndSelect( ctx, str ) "{{{
    " TODO remove needless marks

    let [ ctx, str ] = [ a:ctx, a:str ]
    let [ item, ph ] = [ ctx.item, ctx.leadingPlaceHolder ]

    let marks = ph.isKey ? ph.editMark : ph.mark
    let [ start, end ] = [ XPMpos( marks.start ), XPMpos( marks.end ) ]


    if start == [0, 0] || end == [0, 0]
        return s:Crash()
    endif


    " set str to key place holder or the first normal place holder 
    call XPreplace( start, end, str )

    let xp = ctx.tmpl.ptn

    if str =~ '\V' . xp.lft . '\.\*' . xp.rt
        if 0 != s:BuildPlaceHolders( marks )
            return s:Crash()
        endif

        call s:log.Log( 'rebuild default values' )
        return s:GotoNextItem()
    endif


    call s:XPTupdate()

    let action = s:selectCurrent(ctx)
    call XPMupdateStat()
    return action

endfunction "}}}

fun! s:ApplyDefaultValueToPH( renderContext, filter ) "{{{

    call s:log.Log( "**" )

    let renderContext = a:renderContext
    let leader = renderContext.leadingPlaceHolder

    let str = a:filter


    " popup list, action dictionary or string
    let obj = s:Eval(str) 

    call s:log.Debug( 'filter=' . str, 'filterd=' . string( obj ) )


    if type(obj) == type({})
        " action object
        let rc = s:HandleDefaultValueAction( renderContext, obj )

        return ( rc is -1 ) ? s:FillinLeadingPlaceHolderAndSelect( renderContext, '' ) : rc

    elseif type(obj) == type([])
        " popup list

        if len(obj) == 0
            return s:FillinLeadingPlaceHolderAndSelect( renderContext, '' )
        endif

        " TODO exclude edge?
        
        let marks = leader.isKey ? leader.editMark : leader.mark
        let [ start, end ] = XPMposList( marks.start, marks.end )
        call XPreplace( start, end, '')
        call cursor(start)

        " to pop up, but do not enlarge matching, thus empty string is selected at first
        return XPPopupNew(s:ItemPumCB, {}, obj).popup(col("."), 1, 0)

    else 
        " string
        let filterIndent = matchstr( obj, '\s*\ze\n' )
        let filterText = matchstr( obj, '\n\zs\_.*' )
        let str = s:AdjustIndentAccordingToLine( filterText, filterIndent, XPMpos( renderContext.leadingPlaceHolder.mark.start )[0] )

        return s:FillinLeadingPlaceHolderAndSelect( renderContext, str )

    endif
endfunction "}}}

" return type action
fun! s:InitItem() " {{{
    let renderContext = s:getRenderContext()
    let renderContext.phase = 'inititem'


    " apply default value
    if has_key(renderContext.tmpl.setting.defaultValues, renderContext.item.name)
        return s:ApplyDefaultValueToPH( renderContext, 
                    \renderContext.tmpl.setting.defaultValues[ renderContext.item.name ])

    elseif renderContext.leadingPlaceHolder.ontimeFilter != ''
        return s:ApplyDefaultValueToPH( renderContext, 
                    \renderContext.leadingPlaceHolder.ontimeFilter)


    else
        " TODO needed to fill in?
        let str = renderContext.item.name
        " return s:FillinLeadingPlaceHolderAndSelect( renderContext, str )
        " TODO needed?
        " call XPMupdate()

        " to update the edge to following place holder
        call s:XPTupdate()

        let action = s:selectCurrent(renderContext)
        call XPMupdateStat()

        return action

    endif

endfunction " }}}

fun! s:selectCurrent( renderContext ) "{{{
    let ph = a:renderContext.leadingPlaceHolder
    let marks = ph.isKey ? ph.editMark : ph.mark

    let [ ctl, cbr ] = [ XPMpos( marks.start ), XPMpos( marks.end ) ]

    let a:renderContext.phase = 'fillin'

    if ctl == cbr 
        return ''
    else
        call cursor( ctl )
        call s:XPTvisual()
        if &l:selection == 'exclusive'
            call cursor( cbr )
        else
            if cbr[1] == 1
                call cursor( cbr[0] - 1, col( [ cbr[0] - 1, '$' ] ) )
            else
                call cursor( cbr[0], cbr[1] - 1 )
            endif
        endif

        normal! v


        return s:SelectAction()
    endif

endfunction "}}}


fun! s:CreateStringMask( str ) "{{{

    if a:str == ''
        return ''
    endif

    if !exists( 'b:_xpeval' )
        let b:_xpeval = { 'cache' : {} }
    endif

    if has_key( b:_xpeval.cache, a:str )
        return b:_xpeval.cache[ a:str ]
    endif

    " non-escaped prefix
    let nonEscaped =   '\%(' . '\%(\[^\\]\|\^\)' . '\%(\\\\\)\*' . '\)' . '\@<='

    " non-escaped quotation
    let dqe = '\V\('. nonEscaped . '"\)'
    let sqe = '\V\('. nonEscaped . "'\\)"

    let dptn = dqe.'\_.\{-}\1'

    " let sptn = sqe.'\_.\{-}\1'
    " Note: only ' is escaped by doubling it: ''
    " let sptn = sqe.'\_.\{-}\%(\^\|\[^'']\)\(''''\)\*'''
    let sptn = sqe.'\%(\_[^'']\)\{-}'''

    " create mask hiding all string literal with space
    let mask = substitute(a:str, '[ *]', '+', 'g')
    while 1 "{{{
        let d = match(mask, dptn)
        let s = match(mask, sptn)

        if d == -1 && s == -1
            break
        endif

        if d > -1 && (d < s || s == -1)
            let sub = matchstr(mask, dptn)
            let sub = repeat(' ', len(sub))
            let mask = substitute(mask, dptn, sub, '')
        elseif s > -1
            let sub = matchstr(mask, sptn)
            let sub = repeat(' ', len(sub))
            let mask = substitute(mask, sptn, sub, '')
        endif

    endwhile "}}}

    let b:_xpeval.cache[ a:str ] = mask

    return mask

endfunction "}}}

fun! S2l(a, b)
    return a:a - a:b
endfunction

fun! s:Eval(s, ...) "{{{
    let x = g:XPTobject()
    let ctx = s:getRenderContext()
    let xfunc = x.funcs

    let tmpEvalCtx = { 'typed' : '', 'usingCache' : 1 }

    if a:0 >= 1
        call extend( tmpEvalCtx, a:1, 'force' )
    endif


    " non-escaped prefix
    let nonEscaped =   '\%(' . '\%(\[^\\]\|\^\)' . '\%(\\\\\)\*' . '\)' . '\@<='


    " TODO how to add '$' ?
    let fptn = '\V' . '\w\+(\[^($]\{-})' . '\|' . nonEscaped . '{\w\+(\[^($]\{-})}'
    let vptn = '\V' . nonEscaped . '$\w\+' . '\|' . nonEscaped . '{$\w\+}'

    let patternVarOrFunc = fptn . '\|' . vptn

    let stringMask = s:CreateStringMask( a:s )

    call s:log.Debug( 'string =' . a:s, 'strmask=' . stringMask )




    " TODO simplify me
    let xfunc._ctx = ctx.evalCtx
    let xfunc._ctx.tmpl = ctx.tmpl
    let xfunc._ctx.step = {}
    let xfunc._ctx.namedStep = {}
    let xfunc._ctx.value = ''
    let xfunc._ctx.item = {}
    let xfunc._ctx.leadingPlaceHolder = {}
    if ctx.processing
        let xfunc._ctx.step = ctx.step
        let xfunc._ctx.namedStep = ctx.namedStep
        let xfunc._ctx.name = ctx.item.name
        let xfunc._ctx.fullname = ctx.item.fullname
        let xfunc._ctx.value = tmpEvalCtx.typed
        let xfunc._ctx.item = ctx.item
        let xfunc._ctx.leadingPlaceHolder = ctx.leadingPlaceHolder
    endif




    " parameter string list
    let rangesToEval = {}
    let str = a:s


    while 1

        let matchedIndex = match(stringMask, patternVarOrFunc)
        if matchedIndex == -1
            break
        endif


        let matchedLen = len(matchstr(stringMask, patternVarOrFunc))
        let matched = str[matchedIndex : matchedIndex + matchedLen - 1]


        if matched =~ '^{.*}$'
            let matched = matched[1:-2]
        endif



        if matched[-1:] == ')' && has_key(xfunc, matchstr(matched, '^\w\+'))
            let matched = "xfunc." . matched

        elseif matched[0:0] == '$' && has_key(xfunc, matched)
            let matched = 'xfunc["' . matched . '"]'

        endif


        let contextedMatchedLen = len(matched)


        " remove spanned sub expression
        for i in keys(rangesToEval)
            if i >= matchedIndex && i < matchedIndex + matchedLen
                call remove(rangesToEval, i)
            endif
        endfor

        " add unparsed string
        let rangesToEval[matchedIndex] = contextedMatchedLen


        let stringMask = (matchedIndex == 0 ? "" : stringMask[:matchedIndex-1]) 
                    \ . repeat(' ', contextedMatchedLen)
                    \ . stringMask[matchedIndex + matchedLen :]

        let str  = (matchedIndex == 0 ? "" :  str[:matchedIndex-1])
                    \ . matched
                    \ . str[matchedIndex + matchedLen :]

    endwhile




    let sp = ""
    let last = 0


    let offsetsOfEltsToEval = sort(keys(rangesToEval), "S2l")




    for k in offsetsOfEltsToEval

        let kn = 0 + k
        let vn = 0 + k + rangesToEval[k]


        " unescape \{ and \(
        " match the previous line )} - -..
        let tmp = k == 0 ? "" : (str[last : kn-1])
        " let tmp = substitute(tmp, '\\\(.\)', '\1', 'g')
        " TODO need to unescape '[' ?
        let tmp = g:xptutil.UnescapeChar( tmp, '[{$(' )
        let sp .= tmp


        let evaledResult = eval(str[kn : vn-1])

        if type(evaledResult) != type('')
            call s:log.Log( "Eval:evaluated type is not string but =" . type(evaledResult) . ' '.str[ kn : vn - 1 ] )
            " discard anything else
            return evaledResult
        endif

        let sp .= evaledResult


        let last = vn
    endfor

    let tmp = str[last : ]
    " let tmp = substitute(tmp, '\\\(.\)', '\1', 'g')
    let tmp = g:xptutil.UnescapeChar( tmp, '[{$(' )
    let sp .= tmp

    return sp

endfunction "}}}

fun! s:TextBetween(p1, p2) "{{{
    if a:p1[0] > a:p2[0]
        return ""
    endif

    let [p1, p2] = [a:p1, a:p2]

    if p1[0] == p2[0]
        if p1[1] == p2[1]
            return ""
        else
            call s:log.Log( "content between " . string( [a:p1, a:p2] ) . ' is :' . getline(p1[0])[ p1[1] - 1 : p2[1] - 2] )
            return getline(p1[0])[ p1[1] - 1 : p2[1] - 2]
        endif
    endif


    let r = [ getline(p1[0])[p1[1] - 1:] ] + getline(p1[0]+1, p2[0]-1)

    if p2[1] > 1
        let r += [ getline(p2[0])[:p2[1] - 2] ]
    else
        let r += ['']
    endif

    call s:log.Log( "content between " . string( [a:p1, a:p2] ) . ' is :'.join( r, "\n" ) )
    return join(r, "\n")

endfunction "}}}

" Weird, but that's only way to select content
fun! s:SelectAction() "{{{
    return "\<esc>gv\<C-g>"

    if &l:slm =~ 'cmd'
        return "\<esc>gv"
    else
        return "\<esc>gv\<C-g>"
    endif
endfunction "}}}

fun! s:LeftPos(p) "{{{
    let p = a:p
    if p[1] == 1
        if p[0] > 1
            let p = [p[0]-1, col([p[0]-1, "$"])]
        endif
    else
        let p = [p[0], p[1]-1]
    endif

    let p[1] = max([p[1], 1])
    return p
endfunction "}}}

fun! s:CheckAndBS(k) "{{{
    let x = g:XPTobject()

    let p = [ line( "." ), col( "." ) ]
    let ctl = s:CTL(x)

    if p[0] == ctl[0] && p[1] == ctl[1]
        return ""
    else
        let k= eval('"\<'.a:k.'>"')
        return k
    endif
endfunction "}}}
fun! s:CheckAndDel(k) "{{{
    let x = g:XPTobject()

    let p = getpos(".")[1:2]
    let cbr = s:CBR(x)

    if p[0] == cbr[0] && p[1] == cbr[1]
        return ""
    else
        let k= eval('"\<'.a:k.'>"')
        return k
    endif
endfunction "}}}

fun! s:Goback() "{{{
    let renderContext = s:getRenderContext()
    call cursor( XPMpos( renderContext.leadingPlaceHolder.mark.end ) )

    return ''
endfunction "}}}

fun! s:ApplyMap() " {{{
    let x = g:XPTobject()
    let savedMap = x.savedMap

    " let savedMap.i_bs       = g:MapPush("<bs>", "i", 1)
    " let savedMap.i_c_w      = g:MapPush("<C-w>", "i", 1)
    " let savedMap.i_del      = g:MapPush("<Del>", "i", 1)

    let savedMap.i_nav      = g:MapPush(g:xptemplate_nav_next  , "i", 1)
    let savedMap.s_nav      = g:MapPush(g:xptemplate_nav_next  , "s", 1)
    let savedMap.s_cancel   = g:MapPush(g:xptemplate_nav_cancel, "s", 1)

    let savedMap.s_del      = g:MapPush("<Del>", "s", 1)
    let savedMap.s_bs       = g:MapPush("<bs>", "s", 1)
    let savedMap.s_right    = g:MapPush(g:xptemplate_to_right, "s", 1)

    let savedMap.n_back     = g:MapPush(g:xptemplate_goback, "n", 1)




    " inoremap <silent> <buffer> <bs> <C-r>=<SID>CheckAndBS("bs")<cr>
    " inoremap <silent> <buffer> <C-w> <C-r>=<SID>CheckAndBS("C-w")<cr>
    " inoremap <silent> <buffer> <Del> <C-r>=<SID>CheckAndDel("Del")<cr>

    exe 'inoremap <silent> <buffer> '.g:xptemplate_nav_next  .' <C-r>=<SID>finishCurrentAndGotoNextItem("")<cr>'
    exe 'snoremap <silent> <buffer> '.g:xptemplate_nav_next  .' <Esc>`>a<C-r>=<SID>finishCurrentAndGotoNextItem("")<cr>'
    exe 'snoremap <silent> <buffer> '.g:xptemplate_nav_cancel.' <Esc>i<C-r>=<SID>finishCurrentAndGotoNextItem("clear")<cr>'

    exe 'nnoremap <silent> <buffer> '.g:xptemplate_goback . ' i<C-r>=<SID>Goback()<cr>'

    snoremap <silent> <buffer> <Del> <Del>i
    snoremap <silent> <buffer> <bs> <esc>`>a<bs>
    exe "snoremap <silent> <buffer> ".g:xptemplate_to_right." <esc>`>a"

endfunction " }}}

fun! s:ClearMap() " {{{
    let x = g:XPTobject()
    let savedMap = x.savedMap

    " clear all
    " iunmap <buffer> <bs>
    " iunmap <buffer> <C-w>
    " iunmap <buffer> <Del>
    exe 'iunmap <buffer> '.g:xptemplate_nav_next
    exe 'sunmap <buffer> '.g:xptemplate_nav_next
    exe 'sunmap <buffer> '.g:xptemplate_nav_cancel

    exe 'nunmap <buffer> '.g:xptemplate_goback

    sunmap <buffer> <Del>
    sunmap <buffer> <bs>
    exe "sunmap <buffer> ".g:xptemplate_to_right


    " restore map, reversed order

    call g:MapPop(savedMap.n_back  )

    call g:MapPop(savedMap.s_right )
    call g:MapPop(savedMap.s_bs    )
    call g:MapPop(savedMap.s_del   )

    call g:MapPop(savedMap.s_cancel)
    call g:MapPop(savedMap.s_nav   )
    call g:MapPop(savedMap.i_nav   )

    " call g:MapPop(savedMap.i_del   )
    " call g:MapPop(savedMap.i_c_w   )
    " call g:MapPop(savedMap.i_bs    )

    let x.savedMap = {}

endfunction " }}}



fun! s:CTL(...) "{{{
    let x = a:0 == 1 ? a:1 : g:XPTobject()
    let cp = x.renderContext.pos.curpos
    return copy( cp.start.pos )
endfunction "}}}

fun! s:CBR(...) "{{{
    let x = a:0 == 1 ? a:1 : g:XPTobject()
    let cp = x.renderContext.pos.curpos
    return copy( cp.end.pos )
endfunction "}}}


fun! XPTbufData() "{{{
    return g:XPTobject()
endfunction "}}}


let s:snipScopePrototype = {
      \'ptn' : {'l':'`', 'r':'^'},
      \'indent' : {'type' : 'auto', 'rate' : []},
      \'priority' : s:priorities.lang
      \}

fun! XPTnewSnipScope()
  let x = b:xptemplateData
  let x.snipFileScope = deepcopy( s:snipScopePrototype )

  call s:RedefinePattern()

  return x.snipFileScope
endfunction

fun! XPTsnipScope()
  return g:XPTobject().snipFileScope
endfunction

fun! XPTsnipScopePush()
  let x = g:XPTobject()
  let x.snipFileScopeStack += [x.snipFileScope]
  let x.snipFileScope = XPTnewSnipScope()
endfunction

fun! XPTsnipScopePop()
  let x = g:XPTobject()
  if len(x.snipFileScopeStack) > 0
    let x.snipFileScope = x.snipFileScopeStack[ -1 ]
    call remove( x.snipFileScopeStack, -1 )
  else
    throw "snipFileScopeStack is empty"
  endif
endfunction


" TODO bad name with newTemplateRenderContext
fun! s:createRenderContext(x) "{{{
    call s:log.Log( 'new render context is created' )

    let a:x.renderContext = deepcopy( s:renderContextPrototype )
    let a:x.renderContext.lastTotalLine = line( '$' )
    let a:x.renderContext.markNamePre = "XPTM" . len( a:x.stack ) . '_'
    let a:x.renderContext.marks.tmpl = { 
                \ 'start' : a:x.renderContext.markNamePre . '`tmpl`start', 
                \ 'end'   : a:x.renderContext.markNamePre . '`tmpl`end', }

    return a:x.renderContext
endfunction "}}}

fun! s:getRenderContext(...) "{{{
    let x = a:0 == 1 ? a:1 : g:XPTobject()
    return x.renderContext
endfunction "}}}

fun! g:XPTobject() "{{{
    if !exists("b:xptemplateData")
        let b:xptemplateData = {
                    \    'tmplarr' : [], 
                    \    'normalTemplates' : {}, 
                    \    'funcs' : { '$CURSOR_PH' : 'CURSOR' }, 
                    \    'wrapStartPos' : 0, 
                    \    'wrap' : '', 
                    \    'functionContainer' : {}
                    \}
        let b:xptemplateData.vars = b:xptemplateData.funcs
        let b:xptemplateData.varPriority = {}
        let b:xptemplateData.posStack = []
        let b:xptemplateData.stack = []

        " which letter can be used in template name
        let b:xptemplateData.keyword = '\w'
        let b:xptemplateData.keywordList = []

        let b:xptemplateData.savedMap = {}

        let b:xptemplateData.snipFileScopeStack = []
        let b:xptemplateData.snipFileScope = XPTnewSnipScope()

        call s:createRenderContext( b:xptemplateData )



        " TODO is this the right place to do that?
        call XPMsetBufSortFunction( function( 'XPTmarkCompare' ) )
    endif
    return b:xptemplateData
endfunction "}}}

fun! s:RedefinePattern() "{{{
    let xp = b:xptemplateData.snipFileScope.ptn

    " even number of '\' or start of line
    let nonEscaped = s:nonEscaped

    let xp.lft = nonEscaped . xp.l
    let xp.rt  = nonEscaped . xp.r

    " for search
    let xp.lft_e = nonEscaped. '\\'.xp.l
    let xp.rt_e  = nonEscaped. '\\'.xp.r

    " regular pattern to match any template item.
    " let xp.itemPattern       = xp.lft . '\%(NAME\)' . xp.rt
    " let xp.itemContentPattern= xp.lft . '\zs\%(NAME\)\ze' . xp.rt

    let xp.item_var          = '$\w\+'
    let xp.item_qvar         = '{$\w\+}'
    let xp.item_func         = '\w\+(\.\*)'
    let xp.item_qfunc        = '{\w\+(\.\*)}'
    let xp.itemContent       = '\_.\{-}'
    let xp.item              = xp.lft . '\%(' . xp.itemContent . '\)' . xp.rt

    let xp.itemMarkLPattern  = '\zs'. xp.lft . '\ze\%(' . xp.itemContent . '\)' . xp.rt
    let xp.itemMarkRPattern  = xp.lft . '\%(' . xp.itemContent . '\)\zs' . xp.rt .'\ze'

    " let xp.cursorPattern     = xp.lft . '\%('.s:cursorName.'\)' . xp.rt

    for [k, v] in items(xp)
        if k != "l" && k != "r"
            let xp[k] = '\V' . v
        endif
    endfor

endfunction "}}}

fun! s:PushCtx() "{{{
    let x = g:XPTobject()

    let x.stack += [s:getRenderContext()]
    call s:createRenderContext(x)
endfunction "}}}
fun! s:PopCtx() "{{{
    let x = g:XPTobject()
    let x.renderContext = x.stack[-1]
    call remove(x.stack, -1)
    " call s:HighLightItem(x.renderContext.name, 1)
endfunction "}}}


" TODO accept position argument
fun! s:GetBackPos() "{{{
    return [line(".") - line("$"), col(".") - len(getline("."))]
endfunction "}}}

fun! s:PushBackPos() "{{{
    call add(g:XPTobject().posStack, s:GetBackPos())
endfunction "}}}
fun! s:PopBackPos() "{{{
    let x = g:XPTobject()
    let bp = x.posStack[-1]
    call remove(x.posStack, -1)

    let l = bp[0] + line("$")
    let p = [l, bp[1] + len(getline(l))]
    call cursor(p)
    return p
endfunction "}}}


fun! s:SynNameStack(l, c) "{{{
    let ids = synstack(a:l, a:c)
    if empty(ids)
        return []
    endif

    let names = []
    for id in ids
        let names = names + [synIDattr(id, "name")]
    endfor
    return names
endfunction "}}}

fun! s:CurSynNameStack() "{{{
    return SynNameStack(line("."), col("."))
endfunction "}}}


fun! s:UpdateFollowingPlaceHoldersWith( contentTyped, option ) "{{{
    " TODO if nothing changed, skipping the replace

    call s:log.Debug( 'option=' . string( a:option ) )
    let renderContext = s:getRenderContext()
    call s:log.Debug( 'phase=' . renderContext.phase )

    let useGroupPost = renderContext.phase == 'post' && has_key( a:option, 'post' )
    if useGroupPost
        let groupIndent = a:option.indent
        let groupPost = a:option.post
    else
        let groupPost = a:contentTyped
    endif

    call XPRstartSession()

    let phList = renderContext.item.placeHolders
    for ph in phList
        let filter = ( renderContext.phase == 'post' ? ph.postFilter : ph.ontimeFilter )
        let filter = s:IsFilterEmpty( filter ) ? ph.ontimeFilter : filter

        call s:log.Log( 'UpdateFollowingPlaceHoldersWith : filter=' . filter )

        if !s:IsFilterEmpty( filter )
            let [ filterIndent, filterText ] = s:GetFilterIndentAndText( filter )
            let filtered = s:Eval( filterText, { 'typed' : a:contentTyped } )

            let filtered = s:AdjustIndentAccordingToLine( filtered, filterIndent, XPMpos( ph.mark.start )[0] )

            " TODO ontime filter action support?
        elseif useGroupPost
            let filterIndent = groupIndent
            let filtered = groupPost

            let filtered = s:AdjustIndentAccordingToLine( filtered, filterIndent, XPMpos( ph.mark.start )[0] )

        else
            let filtered = a:contentTyped

        endif



        " call XPreplace( XPMpos( ph.mark.start ), XPMpos( ph.mark.end ), filtered )
        call XPreplaceByMarkInternal( ph.mark.start, ph.mark.end, filtered )

        call s:log.Debug( 'after update 1 place holder:', s:TextBetween( XPMpos( renderContext.marks.tmpl.start ), XPMpos( renderContext.marks.tmpl.end ) ) )
    endfor

    call XPRendSession()

endfunction "}}}

fun! s:IsFilterEmpty( filter )
    return a:filter !~ '\n.'
endfunction


fun! s:GetFilterIndentAndText( filter ) "{{{
    let filterIndent = matchstr( a:filter, '\s*\ze\n' )
    let filterText = matchstr( a:filter, '\n\zs\_.*' )
    return [ filterIndent, filterText ]
endfunction "}}}

fun! s:Crash(...) "{{{

    " try
        " throw ''
    " catch /.*/
        " let stack = matchstr( v:throwpoint, 'function\s\+\zs.\{-}\ze\.\.\%(Fatal\|Error\|Warn\|Info\|Log\|Debug\).*' )
        " let stack = substitute( stack, '<SNR>\d\+_', '', 'g' )
    " endtry

    " throw "crashed"

    let msg = "XPTemplate snippet crashed :" . join( a:000, "\n" ) 

    call XPRend()

    let x = g:XPTobject()

    " let stack = 'snippet stack:'
    " for ctx in x.stack
        " " TODO nicer message
        " let stack .= ctx.tmpl.name . ' -> '
    " endfor
    " let stack .= x.renderContext.tmpl.name

    call s:ClearMap()

    let x.stack = []
    call s:createRenderContext(x)
    call XPMflush()

    " TODO clear highlight

    echohl WarningMsg
    echom msg
    " echom stack
    echohl

    " no post typing action
    return ''
endfunction "}}}

fun! s:fixCrCausedIndentProblem() "{{{
    let renderContext = s:getRenderContext()

    let currentTotalLine = line( '$' )
    let currentPos = [ line( '.' ), col( '.' ) ]
    let currentFollowingSpace = getline( currentPos[0] )[ currentPos[1] - 1 : ]
    let currentFollowingSpace = matchstr( currentFollowingSpace, '^\s*' )

    call s:log.Log( 'lastFollowingSpace=' . string( renderContext.lastFollowingSpace ) )
    call s:log.Log( 'lastTotalLine=' . string( renderContext.lastTotalLine ) )
    call s:log.Log( 'currentTotalLine=' . string( currentTotalLine ) )
    if renderContext.lastFollowingSpace == ''
                \ || renderContext.lastTotalLine >= currentTotalLine

        let renderContext.lastFollowingSpace = currentFollowingSpace
        return

    endif

    " let currentFollowingSpace = matchstr( currentFollowingSpace, '^\s*' )

    if currentFollowingSpace != renderContext.lastFollowingSpace
        call XPreplace( currentPos, 
                    \[ currentPos[0], currentPos[1] + len( currentFollowingSpace ) ], 
                    \renderContext.lastFollowingSpace, 
                    \{ 'doJobs' : 0 } )
        call cursor( currentPos )
    endif

endfunction "}}}

fun! s:XPTupdate(...) "{{{

    let renderContext = s:getRenderContext()

    if renderContext.phase == 'uninit'
        call XPMflush()
        return 0
    endif


    if !renderContext.processing

        " update XPM is necessary
        call XPMupdate()
        " call XPMupdateStat()
        return 0
    endif


    call s:log.Log("XPTupdate called, mode:".mode())
    call s:log.Log( "marks before XPTupdate:\n" . XPMallMark() )

    call s:fixCrCausedIndentProblem()
    


    " TODO hint to indicate whether cursor is at the right place 

    " TODO check current cursor position for crashing or fixing

    let leaderMark = renderContext.leadingPlaceHolder.mark
    let [ start, end ] = [ XPMpos( leaderMark.start ), XPMpos( leaderMark.end ) ]

    if start == [0, 0] || end == [0, 0]
        " call s:log.Info( 'fail to get start/end mark:' . string( [ start, end ] ) . ' of name=' . string( leaderMark ) )
        call s:Crash( 'mark lost :' . string( leaderMark ) )
        return -1
    endif


    call XPMsetLikelyBetween( leaderMark.start, leaderMark.end )

    let rc = XPMupdate()

    let [ start, end ] = [ XPMpos( leaderMark.start ), XPMpos( leaderMark.end ) ]



    let contentTyped = s:TextBetween( start, end )


    if contentTyped ==# renderContext.lastContent
        call s:log.Log( "nothing different typed" )
        call XPMupdateStat()
        return 0
    endif

    call s:log.Log( "typed:".contentTyped )


    call s:CallPlugin("beforeUpdate")

    " update items


    call s:log.Log("-----------------------")
    call s:log.Log("tmpl:", s:TextBetween( XPMpos( renderContext.marks.tmpl.start ), XPMpos( renderContext.marks.tmpl.end ) ))
    call s:log.Log("lastContent=".renderContext.lastContent)
    call s:log.Log("contentTyped=".contentTyped)




    if rc == g:XPM_RET.likely_matched
        " change taken in current focused place holder
        let relPos = s:recordRelativePosToMark( [ line( '.' ), col( '.' ) ], renderContext.leadingPlaceHolder.mark.start )

        call s:log.Log( "marks before updating following:\n" . XPMallMark() )

        " TODO optimize?
        call s:UpdateFollowingPlaceHoldersWith( contentTyped, {} )

        call s:gotoRelativePosToMark( relPos, renderContext.leadingPlaceHolder.mark.start )

    else

        " TODO undo-redo handling

    endif




    call s:CallPlugin('afterUpdate')


    let renderContext.lastContent = contentTyped
    let renderContext.lastTotalLine = line( '$' )

    

    call s:log.Log( "marks after XPTupdate:\n" . XPMallMark() )

    call XPMupdateStat()

endfunction "}}}

fun! s:recordRelativePosToMark( pos, mark ) "{{{
    let p = XPMpos( a:mark )
    if a:pos[0] == p[0] 
        return [0, a:pos[1] - p[1]]
    else
        return [ a:pos[0] - p[0], a:pos[1] ]
    endif
endfunction "}}}

fun! s:gotoRelativePosToMark( rPos, mark ) "{{{
    let p = XPMpos( a:mark )
    if a:rPos[0] == 0
        call cursor( p[0], a:rPos[1] + p[1] )
    else
        call cursor( p[0] + a:rPos[0], a:rPos[1] )
    endif
endfunction "}}}

fun! s:XPTcheck() "{{{
    let x = g:XPTobject()

    if x.wrap != ''
        let x.wrapStartPos = 0
        let x.wrap = ''
    endif
endfunction "}}}

fun! s:XPTtrackFollowingSpace() "{{{
    let renderContext = s:getRenderContext()

    let currentPos = [ line( '.' ), col( '.' ) ]
    let currentFollowingSpace = getline( currentPos[0] )[ currentPos[1] - 1 : ]
    let currentFollowingSpace = matchstr( currentFollowingSpace, '^\s*' )

    let renderContext.lastFollowingSpace = currentFollowingSpace

endfunction "}}}

augroup XPT "{{{
    au!
    au InsertEnter * call <SID>XPTcheck()

    " au CursorHoldI * call <SID>XPTupdate()
    au CursorMovedI * call <SID>XPTupdate()
    au CursorMoved * call <SID>XPTtrackFollowingSpace()

    " InsertEnter is called in normal mode
    " au InsertEnter * call <SID>XPTupdate('n')

augroup END "}}}

fun! g:XPTaddPlugin(event, func) "{{{
    if has_key(s:plugins, a:event)
        call add(s:plugins[a:event], a:func)
    else
        throw "XPT does NOT support event:".a:event
    endif
endfunction "}}}

fun! s:CallPlugin(ev) "{{{
    if !has_key(s:plugins, a:ev)
        throw "calling invalid event:".a:ev
    endif

    let x = g:XPTobject()
    let v = 0

    for f in s:plugins[a:ev]
        let v = g:XPT[f](x)
        " if !v
        " return
        " endif
    endfor

endfunction "}}}

fun! s:Link(fs) "{{{
    let list = split(a:fs, ' ')
    for v in list
        let s:f[v] = function('<SNR>'.s:sid . v)
    endfor
endfunction "}}}

fun! s:SetIfEmpty( dict, name, value ) "{{{
    if !has_key( a:dict, a:name )
        let a:dict[ a:name ] = a:value
    endif
endfunction "}}}

call <SID>Link('TmplRange GetRangeBetween TextBetween GetStaticRange LeftPos')



com! XPTreload call XPTreload()
com! XPTcrash call <SID>Crash()


fun! String( d, ... )
    " circle referencing can not be dealed well yet. 

    let str = string( a:d )
    let str = substitute( str, "\\V'\\%(\\[^']\\|''\\)\\{-}'" . '\s\*:\s\*function\[^)]),\s\*', '', 'g' )

    return str

endfunction


" vim: set sw=4 sts=4 :
