import std;
import gosh_types;

fn is_ident_char(c: u8) -> bool {
    ascii::is_alnum(c) || c == '_'
}

fn is_delim(c: u8) -> bool {
    c == ' ' || c == '\t' || c == '\n' || c == '\r' ||
    c == '|' || c == '&' || c == ';' || c == '<' || c == '>' ||
    c == '(' || c == ')' || c == '{' || c == '}'
}

// Read a here-document delimiter word, honoring quotes and backslash escapes.
// Quotes are removed and reported through `quoted` so the body stays literal.
fn read_heredoc_delim(line: const u8[:], i: i64&, delim: u8[..128]&, quoted: bool&) -> i32 {
    while i < line.len && (line[i] == ' ' || line[i] == '\t') { i++; }
    while i < line.len {
        let ch = line[i];
        if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' ||
           ch == ';' || ch == '|' || ch == '&' || ch == '<' || ch == '>' ||
           ch == '(' || ch == ')' || ch == '{' || ch == '}' { break; }
        if ch == '\\' && i + 1 < line.len {
            quoted = true;
            if delim.len >= 128 { return -1; }
            delim.push(line[i + 1]);
            i += 2;
            continue;
        }
        if ch == '\'' || ch == '"' {
            let q = ch;
            quoted = true;
            i++;
            while i < line.len && line[i] != q {
                if delim.len >= 128 { return -1; }
                delim.push(line[i]);
                i++;
            }
            if i < line.len { i++; }
            continue;
        }
        if delim.len >= 128 { return -1; }
        delim.push(ch);
        i++;
    }
    if delim.len == 0 { return -1; }
    return 0;
}

fn tokenize_line(line: const u8[:], tokens: Token[..64]&, heredocs: Heredoc[..4]&) -> i32 {
    tokens.clear();
    heredocs.clear();
    // Here-documents declared on this command line, terminated on the next one.
    var pending_delims: u8[..128][..4] = [];
    var pending_quoted: i64 = 0;
    var i = 0;
    let len = line.len;

    while i < len {
        let c = line[i];

        // Skip spaces and tabs
        if c == ' ' || c == '\t' || c == '\r' {
            i++;
            continue;
        }

        // Comment
        if c == '#' {
            while i < len && line[i] != '\n' {
                i++;
            }
            continue;
        }

        // Reserve the final slot for EOF, after whitespace/comments are skipped.
        if tokens.len >= 63 {
            print("gosh: input capacity exceeded: tokens (maximum 63)");
            return -1;
        }

        // Newline
        if c == '\n' {
            var tok = Token { kind: TOKEN_NEWLINE };
            format(tok.text, "\n");
            tokens.push(tok);
            i++;

            // Bodies start on the line after the command line that declared them.
            var p = 0;
            while p < pending_delims.len {
                var body: u8[..512] = [];
                var found = false;
                while i < len {
                    let line_start = i;
                    while i < len && line[i] != '\n' { i++; }
                    var content_end = i;
                    if i < len { i++; }
                    if content_end > line_start && line[content_end - 1] == '\r' { content_end--; }
                    if line[line_start..content_end] == pending_delims[p] {
                        found = true;
                        break;
                    }
                    if body.len + (content_end - line_start) + 1 > 512 {
                        print("gosh: input capacity exceeded: here-document body bytes (maximum 512)");
                        return -1;
                    }
                    format(body, line[line_start..content_end]);
                    body.push('\n');
                }
                if !found {
                    print("gosh: syntax error: unterminated here-document (wanted '", pending_delims[p], "')");
                    return -1;
                }
                if heredocs.len >= 4 {
                    print("gosh: input capacity exceeded: here-documents (maximum 4)");
                    return -1;
                }
                var hd = Heredoc { quoted: (pending_quoted & (1 << p)) != 0 };
                format(hd.body, body);
                heredocs.push(hd);
                p++;
            }
            pending_delims.clear();
            pending_quoted = 0;
            continue;
        }

        // Semicolon
        if c == ';' {
            var tok = Token { kind: TOKEN_SEMI };
            format(tok.text, ";");
            tokens.push(tok);
            i++;
            continue;
        }

        // Pipe or OR
        if c == '|' {
            if i + 1 < len && line[i + 1] == '|' {
                var tok = Token { kind: TOKEN_OR };
                format(tok.text, "||");
                tokens.push(tok);
                i += 2;
            } else {
                var tok = Token { kind: TOKEN_PIPE };
                format(tok.text, "|");
                tokens.push(tok);
                i++;
            }
            continue;
        }

        // Ampersand or AND
        if c == '&' {
            if i + 1 < len && line[i + 1] == '&' {
                var tok = Token { kind: TOKEN_AND };
                format(tok.text, "&&");
                tokens.push(tok);
                i += 2;
            } else if i + 1 < len && line[i + 1] == '>' {
                var tok = Token { kind: TOKEN_REDIR_BOTH };
                format(tok.text, "&>");
                tokens.push(tok);
                i += 2;
            } else {
                var tok = Token { kind: TOKEN_AMP };
                format(tok.text, "&");
                tokens.push(tok);
                i++;
            }
            continue;
        }

        // Redirect IN, here-string, or here-document
        if c == '<' {
            if i + 2 < len && line[i + 1] == '<' && line[i + 2] == '<' {
                var tok = Token { kind: TOKEN_REDIR_HERESTR };
                format(tok.text, "<<<");
                tokens.push(tok);
                i += 3;
                continue;
            }
            if i + 1 < len && line[i + 1] == '<' {
                if i + 2 < len && line[i + 2] == '-' {
                    print("gosh: syntax error: tab-stripping here-documents (<<-) are not supported");
                    return -1;
                }
                var tok = Token { kind: TOKEN_REDIR_HEREDOC };
                format(tok.text, "<<");
                tokens.push(tok);
                i += 2;
                var delim: u8[..128] = [];
                var was_quoted = false;
                if read_heredoc_delim(line, i, delim, was_quoted) != 0 {
                    print("gosh: syntax error: expected here-document delimiter");
                    return -1;
                }
                if pending_delims.len >= 4 {
                    print("gosh: input capacity exceeded: here-documents (maximum 4)");
                    return -1;
                }
                pending_delims.push(delim);
                if was_quoted {
                    pending_quoted = pending_quoted | (1 << (pending_delims.len - 1));
                }
                // The parser reads the delimiter as the redirection operand.
                var dtok = Token { kind: TOKEN_WORD };
                format(dtok.text, delim);
                tokens.push(dtok);
                continue;
            }
            var tok = Token { kind: TOKEN_REDIR_IN };
            format(tok.text, "<");
            tokens.push(tok);
            i++;
            continue;
        }

        // Redirect OUT or APPEND
        if c == '>' {
            if i + 1 < len && line[i + 1] == '>' {
                var tok = Token { kind: TOKEN_REDIR_APP };
                format(tok.text, ">>");
                tokens.push(tok);
                i += 2;
            } else if i + 1 < len && line[i + 1] == '&' && i + 2 < len && line[i + 2] == '2' {
                var tok = Token { kind: TOKEN_REDIR_E2O };
                format(tok.text, ">&2");
                tokens.push(tok);
                i += 3;
            } else {
                var tok = Token { kind: TOKEN_REDIR_OUT };
                format(tok.text, ">");
                tokens.push(tok);
                i++;
            }
            continue;
        }

        // 2> or 2>> or 2>&1
        if c == '2' && i + 1 < len && line[i + 1] == '>' {
            if i + 2 < len && line[i + 2] == '>' {
                var tok = Token { kind: TOKEN_REDIR_ERR_APP };
                format(tok.text, "2>>");
                tokens.push(tok);
                i += 3;
            } else if i + 3 < len && line[i + 2] == '&' && line[i + 3] == '1' {
                var tok = Token { kind: TOKEN_REDIR_E2O };
                format(tok.text, "2>&1");
                tokens.push(tok);
                i += 4;
            } else {
                var tok = Token { kind: TOKEN_REDIR_ERR };
                format(tok.text, "2>");
                tokens.push(tok);
                i += 2;
            }
            continue;
        }

        // Parentheses and Braces
        if c == '(' {
            var tok = Token { kind: TOKEN_LPAREN };
            format(tok.text, "(");
            tokens.push(tok);
            i++;
            continue;
        }
        if c == ')' {
            var tok = Token { kind: TOKEN_RPAREN };
            format(tok.text, ")");
            tokens.push(tok);
            i++;
            continue;
        }
        if c == '{' {
            var tok = Token { kind: TOKEN_LBRACE };
            format(tok.text, "{");
            tokens.push(tok);
            i++;
            continue;
        }
        if c == '}' {
            var tok = Token { kind: TOKEN_RBRACE };
            format(tok.text, "}");
            tokens.push(tok);
            i++;
            continue;
        }

        // Word (includes quotes, escapes, variables, $((...)), $(...), `...`)
        var tok = Token { kind: TOKEN_WORD };
        while i < len {
            let ch = line[i];

            // Arithmetic $((...))
            if ch == '$' && i + 2 < len && line[i + 1] == '(' && line[i + 2] == '(' {
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('$');
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('(');
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('(');
                i += 3;
                var depth = 0;
                while i < len {
                    if line[i] == '(' { depth++; }
                    else if line[i] == ')' {
                        if depth == 0 { break; }
                        depth--;
                    }
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                if i + 1 < len && line[i] == ')' && line[i + 1] == ')' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(')');
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(')');
                    i += 2;
                }
                continue;
            }

            // Command substitution $(...)
            if ch == '$' && i + 1 < len && line[i + 1] == '(' {
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('$');
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('(');
                i += 2;
                var depth = 1;
                while i < len && depth > 0 {
                    if line[i] == '(' { depth++; }
                    else if line[i] == ')' {
                        depth--;
                        if depth == 0 {
                            if tok.text.len >= 128 {
                                print("gosh: input capacity exceeded: word bytes (maximum 128)");
                                return -1;
                            }
                            tok.text.push(')');
                            i++;
                            break;
                        }
                    }
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                continue;
            }

            // Command substitution `...`
            if ch == '`' {
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('`');
                i++;
                while i < len && line[i] != '`' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                if i < len && line[i] == '`' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push('`');
                    i++;
                }
                continue;
            }

            // Variable ${...}
            if ch == '$' && i + 1 < len && line[i + 1] == '{' {
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('$');
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('{');
                i += 2;
                while i < len && line[i] != '}' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                if i < len && line[i] == '}' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push('}');
                    i++;
                }
                continue;
            }

            if is_delim(ch) {
                break;
            }
            if ch == '\\' {
                if i + 1 < len {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i + 1]);
                    i += 2;
                } else {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(ch);
                    i++;
                }
                continue;
            }
            if ch == '\'' {
                // Single quote: preserve quotes so expansion engine knows not to expand
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('\'');
                i++;
                while i < len && line[i] != '\'' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                if i < len && line[i] == '\'' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push('\'');
                    i++;
                }
                continue;
            }
            if ch == '"' {
                // Double quote: preserve quotes so expansion engine knows not to glob
                if tok.text.len >= 128 {
                    print("gosh: input capacity exceeded: word bytes (maximum 128)");
                    return -1;
                }
                tok.text.push('"');
                i++;
                while i < len && line[i] != '"' {
                    if line[i] == '\\' && i + 1 < len {
                        let next = line[i + 1];
                        if next == '"' || next == '\\' || next == '$' || next == '`' {
                            if tok.text.len >= 128 {
                                print("gosh: input capacity exceeded: word bytes (maximum 128)");
                                return -1;
                            }
                            tok.text.push('\\');
                            if tok.text.len >= 128 {
                                print("gosh: input capacity exceeded: word bytes (maximum 128)");
                                return -1;
                            }
                            tok.text.push(next);
                            i += 2;
                            continue;
                        }
                    }
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push(line[i]);
                    i++;
                }
                if i < len && line[i] == '"' {
                    if tok.text.len >= 128 {
                        print("gosh: input capacity exceeded: word bytes (maximum 128)");
                        return -1;
                    }
                    tok.text.push('"');
                    i++;
                }
                continue;
            }

            if tok.text.len >= 128 {
                print("gosh: input capacity exceeded: word bytes (maximum 128)");
                return -1;
            }
            tok.text.push(ch);
            i++;
        }

        // Keyword recognition
        if tok.text == "if" { tok.kind = TOKEN_IF; }
        else if tok.text == "then" { tok.kind = TOKEN_THEN; }
        else if tok.text == "elif" { tok.kind = TOKEN_ELIF; }
        else if tok.text == "else" { tok.kind = TOKEN_ELSE; }
        else if tok.text == "fi" { tok.kind = TOKEN_FI; }
        else if tok.text == "while" { tok.kind = TOKEN_WHILE; }
        else if tok.text == "until" { tok.kind = TOKEN_UNTIL; }
        else if tok.text == "for" { tok.kind = TOKEN_FOR; }
        else if tok.text == "in" { tok.kind = TOKEN_IN; }
        else if tok.text == "do" { tok.kind = TOKEN_DO; }
        else if tok.text == "done" { tok.kind = TOKEN_DONE; }
        else if tok.text == "case" { tok.kind = TOKEN_CASE; }
        else if tok.text == "esac" { tok.kind = TOKEN_ESAC; }
        else if tok.text == "function" { tok.kind = TOKEN_FUNCTION; }

        tokens.push(tok);
    }

    if pending_delims.len > 0 {
        print("gosh: syntax error: unterminated here-document (wanted '", pending_delims[0], "')");
        return -1;
    }

    var eof_tok = Token { kind: TOKEN_EOF };
    tokens.push(eof_tok);
    return tokens.len as i32;
}
