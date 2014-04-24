Lexer = require('lex')
words = 0
tags = 0
lexer = new Lexer
lexer.addRule(/\w/, (char)->
    words++
)
lexer.addRule(/<[-_a-zA-Z]*>/, (char)->
    tags++
,[])
module.exports = {
    html: (text)->
        lexer.input = text
        lexer.lex()
}
