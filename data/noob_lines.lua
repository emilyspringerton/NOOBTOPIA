-- data/noob_lines.lua -- every ambient line a noob can say. THIS FILE IS THE SOURCE OF TRUTH for the words.
--
-- SHANKPIT does not keep a copy: scripts/gen_ambient_lines.sh reads this file and generates
-- packages/simulation/ambient_lines.inc, so a line edited here changes what an NPC says in SHANKPIT too, with no
-- second edit. Add a line, re-run the generator, done.
--
-- Format is deliberately boring and machine-readable (the generator is awk, not a Lua parser): one entry per line,
-- exactly `{cat = N, text = "..."}`. Single-line strings only, no embedded quotes, no escapes.
--
-- Categories (PARENA/stdlib/noobtopia/ambient_life.prn, ambient-category-for-mood):
--   0 GREETING   1 QUESTION   2 BANTER   3 COMPLAINT   4 SELF
--
-- BANTER is the widest bucket on purpose: it is what fills a street. The original NOOBTOPIA script had 20 lines with
-- no categories at all; these are those 20, kept, plus more per category so a crowd does not repeat itself.

return {
    -- 0 GREETING
    {cat = 0, text = "Hello!"},
    {cat = 0, text = "Hey there."},
    {cat = 0, text = "Oh, hi."},
    {cat = 0, text = "Morning, I think."},
    {cat = 0, text = "You're new around here."},

    -- 1 QUESTION
    {cat = 1, text = "How are you?"},
    {cat = 1, text = "What brings you here?"},
    {cat = 1, text = "Do you like this game?"},
    {cat = 1, text = "What's your favorite color?"},
    {cat = 1, text = "What's your name?"},
    {cat = 1, text = "Have you seen any good movies lately?"},
    {cat = 1, text = "Have you tried the new update?"},

    -- 2 BANTER
    {cat = 2, text = "I'm doing great!"},
    {cat = 2, text = "This is a nice day."},
    {cat = 2, text = "I like your outfit."},
    {cat = 2, text = "I'm feeling lucky today."},
    {cat = 2, text = "This is my favorite game!"},
    {cat = 2, text = "I hope you're having a great day!"},
    {cat = 2, text = "I could really go for a burger."},
    {cat = 2, text = "I'm looking for something fun to do."},
    {cat = 2, text = "Nice weather for standing around."},
    {cat = 2, text = "I heard the shop got new hats."},

    -- 3 COMPLAINT
    {cat = 3, text = "I'm so bored."},
    {cat = 3, text = "I'm a little lost."},
    {cat = 3, text = "I'm feeling a little down today."},
    {cat = 3, text = "I need a vacation."},
    {cat = 3, text = "My feet hurt."},
    {cat = 3, text = "Nothing ever happens here."},

    -- 4 SELF
    {cat = 4, text = "Okay. Okay. That's fine."},
    {cat = 4, text = "Did anyone else hear that?"},
    {cat = 4, text = "Just keep walking."},
    {cat = 4, text = "Nope. Nope nope nope."},
}
