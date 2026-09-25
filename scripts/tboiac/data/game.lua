-- Shared game data: bosses, common enemies, room types, curses, stages.
local data = {}

-- { name, type, variant }
data.BOSSES = {
    { "Monstro", 20, 0 }, { "Monstro II", 43, 0 }, { "Larry Jr.", 19, 0 }, { "The Hollow", 19, 1 },
    { "Gurdy", 36, 0 }, { "Gurdy Jr.", 99, 0 }, { "Mama Gurdy", 266, 0 }, { "Duke of Flies", 67, 0 },
    { "The Husk", 67, 1 }, { "Peep", 68, 0 }, { "The Bloat", 68, 1 }, { "Chub", 28, 0 }, { "C.H.A.D.", 28, 1 },
    { "Carrion Queen", 28, 2 }, { "Gemini", 79, 0 }, { "Steven", 79, 1 }, { "Blighted Ovum", 79, 2 },
    { "Pin", 62, 0 }, { "Scolex", 62, 1 }, { "The Frail", 62, 2 }, { "Wormwood", 62, 3 },
    { "Famine", 63, 0 }, { "Pestilence", 64, 0 }, { "War", 65, 0 }, { "Conquest", 65, 1 }, { "Death", 66, 0 },
    { "Fistula", 71, 0 }, { "Teratoma", 71, 1 }, { "Blastocyst", 74, 0 }, { "Lokii", 69, 0 },
    { "Mask of Infamy", 97, 0 }, { "The Widow", 100, 0 }, { "The Wretched", 100, 1 },
    { "Daddy Long Legs", 101, 0 }, { "Triachnid", 101, 1 }, { "The Haunt", 260, 0 }, { "Dingle", 261, 0 },
    { "Dangle", 261, 1 }, { "Mega Maw", 262, 0 }, { "The Gate", 263, 0 }, { "Mega Fatty", 264, 0 },
    { "The Cage", 265, 0 }, { "Dark One", 267, 0 }, { "The Adversary", 268, 0 }, { "Polycephalus", 269, 0 },
    { "Mr. Fred", 270, 0 }, { "Uriel", 271, 0 }, { "Gabriel", 272, 0 }, { "The Fallen", 81, 0 },
    { "Krampus", 81, 1 }, { "The Stain", 401, 0 }, { "Brownie", 402, 0 }, { "The Forsaken", 403, 0 },
    { "Little Horn", 404, 0 }, { "Rag Man", 405, 0 }, { "Rag Mega", 409, 0 }, { "Sisters Vis", 410, 0 },
    { "Big Horn", 411, 0 }, { "The Matriarch", 413, 0 },
    { "Reap Creep", 900, 0 }, { "Lil Blub", 901, 0 }, { "The Rainmaker", 902, 0 }, { "The Visage", 903, 0 },
    { "The Siren", 904, 0 }, { "The Heretic", 905, 0 }, { "Hornfel", 906, 0 }, { "Great Gideon", 907, 0 },
    { "Baby Plum", 908, 0 }, { "The Scourge", 909, 0 }, { "Chimera", 910, 0 }, { "Rotgut", 911, 0 },
    { "Min-Min", 913, 0 }, { "Clog", 914, 0 }, { "Singe", 915, 0 }, { "Bumbino", 916, 0 },
    { "Colostomia", 917, 0 }, { "Turdlet", 918, 0 }, { "Raglich", 919, 0 }, { "Horny Boys", 920, 0 },
    { "Clutch", 921, 0 },
    { "Mom", 45, 0 }, { "Mom's Heart", 78, 0 }, { "It Lives", 78, 1 }, { "Satan", 84, 0 }, { "Isaac", 102, 0 },
    { "???", 102, 1 }, { "The Lamb", 273, 0 }, { "Mega Satan", 274, 0 }, { "Hush", 407, 0 },
    { "Ultra Greed", 406, 0 }, { "Ultra Greedier", 406, 1 }, { "Delirium", 412, 0 }, { "Mother", 912, 0 },
    { "Dogma", 950, 0 }, { "The Beast", 951, 0 },
}

-- Common enemies: { name, type, variant }
data.ENEMIES = {
    { "Gaper", 10, 0 }, { "Gusher", 11, 0 }, { "Horf", 12, 0 }, { "Fly", 13, 0 }, { "Pooter", 14, 0 },
    { "Clotty", 15, 0 }, { "Mulligan", 16, 0 }, { "Attack Fly", 18, 0 }, { "Hive", 22, 0 },
    { "Charger", 23, 0 }, { "Globin", 24, 0 }, { "Boom Fly", 25, 0 }, { "Maw", 26, 0 }, { "Host", 27, 0 },
    { "Hopper", 29, 0 }, { "Boil", 30, 0 }, { "Spitty", 31, 0 }, { "Leaper", 34, 0 }, { "Baby", 38, 0 },
    { "Vis", 39, 0 }, { "Knight", 41, 0 }, { "Leech", 55, 0 }, { "Lump", 56, 0 }, { "Spider", 85, 0 },
    { "Big Spider", 94, 0 },
}

data.ROOM_TYPES = {
    { "rt_default", RoomType.ROOM_DEFAULT }, { "rt_treasure", RoomType.ROOM_TREASURE },
    { "rt_shop", RoomType.ROOM_SHOP }, { "rt_boss", RoomType.ROOM_BOSS },
    { "rt_miniboss", RoomType.ROOM_MINIBOSS }, { "rt_secret", RoomType.ROOM_SECRET },
    { "rt_supersecret", RoomType.ROOM_SUPERSECRET }, { "rt_ultrasecret", RoomType.ROOM_ULTRASECRET },
    { "rt_arcade", RoomType.ROOM_ARCADE }, { "rt_curse", RoomType.ROOM_CURSE },
    { "rt_challenge", RoomType.ROOM_CHALLENGE }, { "rt_library", RoomType.ROOM_LIBRARY },
    { "rt_sacrifice", RoomType.ROOM_SACRIFICE }, { "rt_isaacs", RoomType.ROOM_ISAACS },
    { "rt_barren", RoomType.ROOM_BARREN }, { "rt_chest", RoomType.ROOM_CHEST },
    { "rt_dice", RoomType.ROOM_DICE }, { "rt_planetarium", RoomType.ROOM_PLANETARIUM },
}

-- { display name, stage number, stage-type suffix for the `stage` console command }
data.STAGES = {
    { "Basement I", 1, "" }, { "Basement II", 2, "" }, { "Cellar I", 1, "a" }, { "Cellar II", 2, "a" },
    { "Burning Basement I", 1, "b" }, { "Burning Basement II", 2, "b" },
    { "Downpour I", 1, "c" }, { "Downpour II", 2, "c" }, { "Dross I", 1, "d" }, { "Dross II", 2, "d" },
    { "Caves I", 3, "" }, { "Caves II", 4, "" }, { "Catacombs I", 3, "a" }, { "Catacombs II", 4, "a" },
    { "Flooded Caves I", 3, "b" }, { "Flooded Caves II", 4, "b" },
    { "Mines I", 3, "c" }, { "Mines II", 4, "c" }, { "Ashpit I", 3, "d" }, { "Ashpit II", 4, "d" },
    { "Depths I", 5, "" }, { "Depths II", 6, "" }, { "Necropolis I", 5, "a" }, { "Necropolis II", 6, "a" },
    { "Dank Depths I", 5, "b" }, { "Dank Depths II", 6, "b" },
    { "Mausoleum I", 5, "c" }, { "Mausoleum II", 6, "c" }, { "Gehenna I", 5, "d" }, { "Gehenna II", 6, "d" },
    { "Womb I", 7, "" }, { "Womb II", 8, "" }, { "Utero I", 7, "a" }, { "Utero II", 8, "a" },
    { "Scarred Womb I", 7, "b" }, { "Scarred Womb II", 8, "b" },
    { "Corpse I", 7, "c" }, { "Corpse II", 8, "c" },
    { "Blue Womb", 9, "" }, { "Sheol", 10, "" }, { "Cathedral", 10, "a" },
    { "Dark Room", 11, "" }, { "The Chest", 11, "a" }, { "The Void", 12, "" }, { "Home", 13, "" },
}

data.CURSES = {
    { "curse_darkness", LevelCurse.CURSE_OF_DARKNESS }, { "curse_labyrinth", LevelCurse.CURSE_OF_LABYRINTH },
    { "curse_lost", LevelCurse.CURSE_OF_THE_LOST }, { "curse_unknown", LevelCurse.CURSE_OF_THE_UNKNOWN },
    { "curse_cursed", LevelCurse.CURSE_OF_THE_CURSED }, { "curse_maze", LevelCurse.CURSE_OF_MAZE },
    { "curse_blind", LevelCurse.CURSE_OF_BLIND }, { "curse_giant", LevelCurse.CURSE_OF_GIANT },
}

-- Characters offered in the menu: { PlayerType, i18n-free display name }.
data.CHARACTERS = {
    { 0, "Isaac" }, { 1, "Magdalene" }, { 2, "Cain" }, { 3, "Judas" }, { 4, "???" }, { 5, "Eve" },
    { 6, "Samson" }, { 7, "Azazel" }, { 8, "Lazarus" }, { 9, "Eden" }, { 10, "The Lost" },
    { 13, "Lilith" }, { 14, "Keeper" }, { 15, "Apollyon" }, { 16, "The Forgotten" }, { 18, "Bethany" },
    { 19, "Jacob & Esau" },
    { 21, "T. Isaac" }, { 22, "T. Magdalene" }, { 23, "T. Cain" }, { 24, "T. Judas" }, { 25, "T. ???" },
    { 26, "T. Eve" }, { 27, "T. Samson" }, { 28, "T. Azazel" }, { 29, "T. Lazarus" }, { 30, "T. Eden" },
    { 31, "T. Lost" }, { 32, "T. Lilith" }, { 33, "T. Keeper" }, { 34, "T. Apollyon" },
    { 35, "T. Forgotten" }, { 36, "T. Bethany" }, { 37, "T. Jacob" },
}

return data
