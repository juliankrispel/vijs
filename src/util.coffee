module.exports = {
    escape: (str) ->
        div = document.createElement('div')
        div.appendChild(document.createTextNode(str))
        div.innerHTML
 
    unescape: (escapedStr) ->
        div = document.createElement('div')
        div.innerHTML = escapedStr
        child = div.childNodes[0]
        if child.nodeValue then child  
        else ''
}
