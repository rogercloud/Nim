#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## A simple XML tree. More efficient and simpler than the DOM.

import macros, strtabs

type
  PXmlNode* = ref TXmlNode ## an XML tree consists of ``PXmlNode``'s. 
  
  TXmlNodeKind* = enum  ## different kinds of ``PXmlNode``'s
    xnText,             ## a text element
    xnElement,          ## an element with 0 or more children
    xnCData,            ## a CDATA node
    xnEntity,           ## an entity (like ``&thing;``)
    xnComment           ## an XML comment
  
  PXmlAttributes* = PStringTable ## an alias for a string to string mapping
  
  TXmlNode {.pure, final, acyclic.} = object 
    case k: TXmlNodeKind
    of xnText, xnComment, xnCData, xnEntity: 
      fText: string
    of xnElement:
      fTag: string
      s: seq[PXmlNode]
      fAttr: PXmlAttributes
    fClientData: int              ## for other clients
  
proc newXmlNode(kind: TXmlNodeKind): PXmlNode = 
  ## creates a new ``PXmlNode``.
  new(result)
  result.k = kind

proc newElement*(tag: string): PXmlNode = 
  ## creates a new ``PXmlNode`` of kind ``xnText`` with the given `tag`.
  result = newXmlNode(xnElement)
  result.fTag = tag
  result.s = @[]
  # init attributes lazily to safe memory

proc newText*(text: string): PXmlNode = 
  ## creates a new ``PXmlNode`` of kind ``xnText`` with the text `text`.
  result = newXmlNode(xnText)
  result.fText = text

proc newComment*(comment: string): PXmlNode = 
  ## creates a new ``PXmlNode`` of kind ``xnComment`` with the text `comment`.
  result = newXmlNode(xnComment)
  result.fText = comment

proc newCData*(cdata: string): PXmlNode = 
  ## creates a new ``PXmlNode`` of kind ``xnComment`` with the text `cdata`.
  result = newXmlNode(xnCData)
  result.fText = cdata

proc newEntity*(entity: string): PXmlNode = 
  ## creates a new ``PXmlNode`` of kind ``xnEntity`` with the text `entity`.
  result = newXmlNode(xnCData)
  result.fText = entity

proc text*(n: PXmlNode): string {.inline.} = 
  ## gets the associated text with the node `n`. `n` can be a CDATA, Text,
  ## comment, or entity node.
  assert n.k in {xnText, xnComment, xnCData, xnEntity}
  result = n.fText

proc tag*(n: PXmlNode): string {.inline.} = 
  ## gets the tag name of `n`. `n` has to be an ``xnElement`` node.
  assert n.k == xnElement
  result = n.fTag
    
proc add*(father, son: PXmlNode) {.inline.} = 
  ## adds the child `son` to `father`.
  add(father.s, son)
  
proc len*(n: PXmlNode): int {.inline.} = 
  ## returns the number `n`'s children.
  if n.k == xnElement: result = len(n.s)

proc kind*(n: PXmlNode): TXmlNodeKind {.inline.} =
  ## returns `n`'s kind.
  result = n.k

proc `[]`* (n: PXmlNode, i: int): PXmlNode {.inline.} = 
  ## returns the `i`'th child of `n`.
  assert n.k == xnElement
  result = n.s[i]

iterator items*(n: PXmlNode): PXmlNode {.inline.} = 
  ## iterates over any child of `n`.
  assert n.k == xnElement
  for i in 0 .. n.len-1: yield n[i]

proc attr*(n: PXmlNode): PXmlAttributes {.inline.} = 
  ## gets the attributes belonging to `n`.
  assert n.k == xnElement
  result = n.fAttr
  
proc `attr=`*(n: PXmlNode, attr: PXmlAttributes) {.inline.} = 
  ## sets the attributes belonging to `n`.
  assert n.k == xnElement
  n.fAttr = attr

proc attrLen*(n: PXmlNode): int {.inline.} = 
  ## returns the number of `n`'s attributes.
  assert n.k == xnElement
  if not isNil(n.fAttr): result = len(n.fAttr)

proc clientData*(n: PXmlNode): int {.inline.} =
  ## gets the client data of `n`. The client data field is used by the HTML
  ## parser and generator.
  result = n.fClientData

proc `clientData=`*(n: PXmlNode, data: int) {.inline.} = 
  ## sets the client data of `n`. The client data field is used by the HTML
  ## parser and generator.
  n.fClientData = data

proc addEscaped*(result: var string, s: string) = 
  ## same as ``result.add(escape(s))``, but more efficient.
  for c in items(s):
    case c
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '&': result.add("&amp;")
    of '"': result.add("&quot;")
    else: result.add(c)

proc escape*(s: string): string = 
  ## escapes `s` for inclusion into an XML document. 
  ## Escapes these characters:
  ##
  ## ------------    -------------------
  ## char            is converted to
  ## ------------    -------------------
  ##  ``<``          ``&lt;``
  ##  ``>``          ``&gt;``
  ##  ``&``          ``&amp;``
  ##  ``"``          ``&quot;``
  ## ------------    -------------------
  result = newString(s.len)
  setLen(result, 0)
  addEscaped(result, s)
  
proc addIndent(result: var string, indent: int) = 
  result.add("\n")
  for i in 1..indent: result.add(' ')
  
proc noWhitespace(n: PXmlNode): bool =
  #for i in 1..n.len-1:
  #  if n[i].kind != n[0].kind: return true
  for i in 0..n.len-1:
    if n[i].kind in {xnText, xnEntity}: return true
  
proc add*(result: var string, n: PXmlNode, indent = 0, indWidth = 2) = 
  ## adds the textual representation of `n` to `result`.
  if n == nil: return
  case n.k
  of xnElement:
    result.add('<')
    result.add(n.fTag)
    if not isNil(n.fAttr): 
      for key, val in pairs(n.fAttr): 
        result.add(' ')
        result.add(key)
        result.add("=\"")
        result.addEscaped(val)
        result.add('"')
    if n.len > 0:
      result.add('>')
      if n.len > 1:
        if noWhitespace(n):
          # for mixed leaves, we cannot output whitespace for readability,
          # because this would be wrong. For example: ``a<b>b</b>`` is
          # different from ``a <b>b</b>``.
          for i in 0..n.len-1: result.add(n[i], indent+indWidth, indWidth)
        else: 
          for i in 0..n.len-1:
            result.addIndent(indent+indWidth)
            result.add(n[i], indent+indWidth, indWidth)
          result.addIndent(indent)
      else:
        result.add(n[0], indent+indWidth, indWidth)
      result.add("</")
      result.add(n.fTag)
      result.add(">")
    else: 
      result.add(" />")
  of xnText:
    result.addEscaped(n.fText)
  of xnComment:
    result.add("<!-- ")
    result.addEscaped(n.fText)
    result.add(" -->")
  of xnCDATA:
    result.add("<![CDATA[")
    result.add(n.fText)
    result.add("]]>")
  of xnEntity:
    result.add('&')
    result.add(n.fText)
    result.add(';')

const
  xmlHeader* = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n" 
    ## header to use for complete XML output

proc `$`*(n: PXmlNode): string =
  ## converts `n` into its string representation. No ``<$xml ...$>`` declaration
  ## is produced, so that the produced XML fragments are composable.
  result = ""
  result.add(n)

proc newXmlTree*(tag: string, children: openArray[PXmlNode],
                 attributes: PXmlAttributes = nil): PXmlNode = 
  ## creates a new XML tree with `tag`, `children` and `attributes`
  result = newXmlNode(xnElement)
  result.fTag = tag
  newSeq(result.s, children.len)
  for i in 0..children.len-1: result.s[i] = children[i]
  result.fAttr = attributes
  
proc xmlConstructor(e: PNimrodNode): PNimrodNode {.compileTime.} =
  expectLen(e, 2)
  var a = e[1]
  if a.kind == nnkCall:
    result = newCall("newXmlTree", toStrLit(a[0]))
    var attrs = newNimNode(nnkBracket, a)
    var newStringTabCall = newCall("newStringTable", attrs, 
                                   newIdentNode("modeCaseSensitive"))
    var elements = newNimNode(nnkBracket, a)
    for i in 1..a.len-1:
      if a[i].kind == nnkExprEqExpr:
        attrs.add(toStrLit(a[i][0]))
        attrs.add(a[i][1])
        echo repr(attrs)
      else:
        elements.add(a[i])
    result.add(elements)
    if attrs.len > 1: 
      echo repr(newStringTabCall)
      result.add(newStringTabCall)
  else:
    result = newCall("newXmlTree", toStrLit(a))

macro `<>`*(x: expr): expr = 
  ## Constructor macro for XML. Example usage:
  ##
  ## .. code-block:: nimrod
  ##   <>a(href="http://force7.de/nimrod", "Nimrod rules.")
  ##
  ## Produces an XML tree for::
  ##
  ##  <a href="http://force7.de/nimrod">Nimrod rules.</a>
  ##
  result = xmlConstructor(x)

