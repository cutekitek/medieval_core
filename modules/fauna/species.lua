-- Animal species definitions used by the medieval_core:animal component
--
-- temper:
--   passive  - flees only when hurt
--   shy      - also runs (or flies) away from a player within shy_radius,
--              unless the player holds its lure item
--   neutral  - fights back when hurt or when a player comes within aggro_radius
--   hostile  - hunts players within aggro_radius
-- habitats: chunk habitat (see fauna/spawning) -> spawn weight
-- breed: a farm animal (husbandry/husbandry): eats and drinks from troughs and
--   breeds when fed and watered. item - fed by hand it counts as a meal (and
--   makes a young one grow); love_time - seconds the pair looks for each
--   other; cooldown - seconds before the parents breed again; grow_time -
--   seconds a young one takes to grow up; feed_growth - share of grow_time a
--   young one gains from a hand feeding; baby_scale - its size
-- voice: a call now and then while active (sounds/medieval_core/<name>), every
--   {min, max} seconds; it is also heard, higher, when the animal is hurt
local this = {}

this.cow = {
    voice = {name = "cow", every = {12, 35}, volume = 0.9},
    entity = "medieval_core:cow",
    health = 10,
    temper = "passive",
    walk_speed = 14,      -- core:mob movement_speed while wandering
    flee_speed = 26,
    gait = 0.9,           -- gait cycles per block travelled
    wander_radius = 7,
    lure_item = "medieval_core:plant_fiber",
    tracks = {walk = "mw_cow_walk", idle = "mw_cow_graze"},
    loot = {
        {item = "medieval_core:raw_beef", min = 1, max = 3},
        {item = "medieval_core:hide", min = 1, max = 2},
    },
    breed = {
        item = "medieval_core:wheat",
        love_time = 30,
        cooldown = 1440,      -- a game day
        grow_time = 1440,
        feed_growth = 0.1,
        baby_scale = 0.5,
    },
    herd = {2, 4},
    habitats = {plains = 3, forest = 1},
}

-- Minecraft-like sheep: follows a player holding wheat, now and then crops
-- the grass it stands on (grass block -> dirt), which regrows the wool of a
-- shorn sheep. A knife shears it. Breeds like the other farm animals; a lamb
-- grows up in grow_time seconds (faster when it grazes or is fed).
this.sheep = {
    voice = {name = "sheep", every = {10, 30}, volume = 0.8},
    entity = "medieval_core:sheep",
    health = 8,
    temper = "passive",
    walk_speed = 13,
    flee_speed = 26,
    gait = 1.1,
    wander_radius = 7,
    lure_item = "medieval_core:wheat",
    tracks = {walk = "mw_cow_walk", idle = "mw_sheep_graze", eat = "mw_sheep_eat"},
    loot = {
        {item = "medieval_core:raw_mutton", min = 1, max = 2},
    },
    wool = {
        item = "medieval_core:wool",
        drop = 1,             -- when killed unshorn
        shear = {1, 3},       -- per shearing
    },
    graze = {
        interval = 50,        -- seconds between meals on average (a lamb: 5)
        time = 2.0,           -- head down this long
        lamb_growth = 60,     -- seconds a lamb grows up sooner per meal
    },
    breed = {
        item = "medieval_core:wheat",
        love_time = 30,
        cooldown = 1440,
        grow_time = 1200,     -- a lamb becomes a sheep (20 minutes)
        feed_growth = 0.1,    -- share of grow_time a fed lamb gains
        baby_scale = 0.5,
    },
    herd = {2, 4},
    habitats = {plains = 2.5, forest = 1, taiga = 1, tundra = 0.3},
}

this.chicken = {
    voice = {name = "chicken", every = {6, 18}, volume = 0.6},
    entity = "medieval_core:chicken",
    health = 4,
    temper = "passive",
    walk_speed = 12,
    flee_speed = 24,
    gait = 2.5,
    wander_radius = 5,
    lure_item = "medieval_core:berries",
    tracks = {walk = "mw_chicken_walk", idle = "mw_chicken_peck", air = "mw_chicken_flap"},
    loot = {
        {item = "medieval_core:raw_chicken", count = 1},
        {item = "medieval_core:feather", min = 0, max = 2},
    },
    breed = {
        item = "medieval_core:wheat_seeds",
        love_time = 30,
        cooldown = 1440,
        grow_time = 1200,
        feed_growth = 0.1,
        baby_scale = 0.5,
    },
    herd = {2, 5},
    habitats = {plains = 2, forest = 1.5},
    -- seconds between eggs
    lay_interval = {300, 600},
    lay_item = "medieval_core:egg",
}

this.horse = {
    voice = {name = "horse", every = {15, 40}, volume = 0.9},
    entity = "medieval_core:horse",
    health = 14,
    temper = "shy",
    shy_radius = 7,
    walk_speed = 16,
    flee_speed = 40,
    gait = 0.7,
    wander_radius = 9,
    lure_item = "medieval_core:plant_fiber",
    tracks = {walk = "mw_horse_walk", idle = "mw_horse_graze"},
    variants = {
        {["$coat"] = "entities/mw_horse_bay", ["$mane"] = "entities/mw_horse_bay_mane",
         ["$face"] = "entities/mw_horse_bay_face"},
        {["$coat"] = "entities/mw_horse_chestnut", ["$mane"] = "entities/mw_horse_chestnut_mane",
         ["$face"] = "entities/mw_horse_chestnut_face"},
        {["$coat"] = "entities/mw_horse_grey", ["$mane"] = "entities/mw_horse_grey_mane",
         ["$face"] = "entities/mw_horse_grey_face"},
        {["$coat"] = "entities/mw_horse_black", ["$mane"] = "entities/mw_horse_black_mane",
         ["$face"] = "entities/mw_horse_black_face"},
    },
    -- the whole herd shares one coat
    herd_variant = true,
    loot = {
        {item = "medieval_core:raw_meat", min = 2, max = 4},
        {item = "medieval_core:hide", min = 1, max = 3},
    },
    breed = {
        item = "medieval_core:wheat",
        love_time = 30,
        cooldown = 1440,
        grow_time = 1800,
        feed_growth = 0.1,
        baby_scale = 0.55,
    },
    herd = {3, 6},
    habitats = {plains = 2.5},
}

this.brown_bear = {
    voice = {name = "bear", every = {15, 40}, volume = 0.35},
    roar = "bear_roar",       -- when it charges
    roar_volume = 0.45,
    entity = "medieval_core:brown_bear",
    health = 30,
    temper = "neutral",
    aggro_radius = 4,     -- comes too close -> attack
    lose_radius = 18,
    walk_speed = 12,
    chase_speed = 30,
    flee_speed = 30,
    gait = 0.6,
    wander_radius = 10,
    attack = {damage = 3, reach = 1.0, cooldown = 1.3, knockback = 7},
    tracks = {walk = "mw_bear_walk", idle = "mw_bear_sniff", attack = "mw_bear_attack"},
    loot = {
        {item = "medieval_core:raw_meat", min = 3, max = 5},
        {item = "medieval_core:fur", min = 1, max = 2},
    },
    herd = {1, 1},
    predator = true,
    habitats = {forest = 0.5, taiga = 0.8},
}

this.polar_bear = {
    voice = {name = "bear", every = {15, 40}, volume = 0.35, pitch = 0.9},
    roar = "bear_roar",       -- when it charges
    roar_volume = 0.45,
    entity = "medieval_core:polar_bear",
    health = 34,
    temper = "hostile",
    aggro_radius = 14,
    lose_radius = 24,
    walk_speed = 12,
    chase_speed = 32,
    flee_speed = 32,
    gait = 0.55,
    wander_radius = 12,
    attack = {damage = 4, reach = 1.1, cooldown = 1.5, knockback = 8},
    tracks = {walk = "mw_bear_walk", idle = "mw_bear_sniff", attack = "mw_bear_attack"},
    loot = {
        {item = "medieval_core:raw_meat", min = 3, max = 6},
        {item = "medieval_core:fur", min = 2, max = 3},
    },
    herd = {1, 2},
    predator = true,
    habitats = {tundra = 0.8},
}

this.squirrel = {
    voice = {name = "squirrel", every = {8, 25}, volume = 0.5},
    entity = "medieval_core:squirrel",
    health = 3,
    temper = "shy",
    shy_radius = 6,
    walk_speed = 16,
    flee_speed = 34,
    gait = 1.8,
    wander_radius = 6,
    hop = true,           -- moves in small jumps
    lure_item = "medieval_core:berries",
    tracks = {walk = "mw_squirrel_hop", idle = "mw_squirrel_sit"},
    loot = {
        {item = "medieval_core:raw_game", count = 1},
        {item = "medieval_core:fur", min = 0, max = 1},
    },
    herd = {1, 3},
    near_trees = true,
    habitats = {forest = 2, taiga = 2},
}

-- birds: walk/peck on the ground, take off when startled or bored, fly
-- between a few waypoints and land on the ground or on a tree crown
this.crow = {
    voice = {name = "crow", every = {8, 25}, volume = 0.8},
    entity = "medieval_core:crow",
    health = 3,
    temper = "shy",
    shy_radius = 7,
    walk_speed = 8,
    flee_speed = 8,
    gait = 3.0,
    wander_radius = 4,
    flight = {speed = 7.5, altitude = {5, 14}, waypoints = {2, 5}, rest = {6, 20}},
    tracks = {walk = "mw_chicken_walk", idle = "mw_chicken_peck", fly = "mw_bird_fly"},
    loot = {
        {item = "medieval_core:raw_game", count = 1},
        {item = "medieval_core:feather", min = 1, max = 2},
    },
    herd = {3, 6},
    habitats = {plains = 1.2, forest = 0.8, taiga = 0.8, tundra = 0.4, desert = 0.4},
}

this.parrot = {
    voice = {name = "parrot", every = {6, 20}, volume = 0.7},
    entity = "medieval_core:parrot",
    health = 3,
    temper = "shy",
    shy_radius = 5,
    walk_speed = 7,
    flee_speed = 7,
    gait = 3.0,
    wander_radius = 3,
    flight = {speed = 6.5, altitude = {4, 12}, waypoints = {1, 4}, rest = {8, 25}, perch = "leaves"},
    tracks = {walk = "mw_bird_hop", idle = "mw_parrot_bob", fly = "mw_bird_fly"},
    variants = {
        {["$plumage"] = "entities/mw_parrot_scarlet", ["$wing"] = "entities/mw_parrot_scarlet_wing",
         ["$face"] = "entities/mw_parrot_scarlet_face"},
        {["$plumage"] = "entities/mw_parrot_blue", ["$wing"] = "entities/mw_parrot_blue_wing",
         ["$face"] = "entities/mw_parrot_blue_face"},
        {["$plumage"] = "entities/mw_parrot_green", ["$wing"] = "entities/mw_parrot_green_wing",
         ["$face"] = "entities/mw_parrot_green_face"},
    },
    loot = {
        {item = "medieval_core:raw_game", count = 1},
        {item = "medieval_core:feather", min = 1, max = 3},
    },
    herd = {2, 4},
    habitats = {tropics = 3},
}

this.owl = {
    voice = {name = "owl", every = {10, 30}, volume = 0.7},
    entity = "medieval_core:owl",
    health = 4,
    temper = "shy",
    shy_radius = 4,
    walk_speed = 6,
    flee_speed = 6,
    gait = 2.0,
    wander_radius = 2,
    nocturnal = true,     -- flies at night, sits still by day
    flight = {speed = 7.0, altitude = {4, 10}, waypoints = {3, 6}, rest = {10, 30}, perch = "leaves"},
    tracks = {walk = "mw_bird_hop", idle = "mw_owl_look", fly = "mw_bird_fly"},
    loot = {
        {item = "medieval_core:raw_game", count = 1},
        {item = "medieval_core:feather", min = 1, max = 3},
    },
    herd = {1, 1},
    near_trees = true,
    habitats = {taiga = 0.7, forest = 0.6},
}

-- Fish (medieval_core:fish component, not the land animal AI): a school spawns
-- in deep enough water of any habitat (fauna/spawning.populate_water) and
-- keeps to the water around its spawn point. Out of water it flops about and
-- suffocates. No `habitats`: never picked by the land spawning.
this.fish = {
    entity = "medieval_core:fish",
    aquatic = true,
    health = 2,
    swim_speed = {0.8, 1.6},
    flee_speed = 4.0,
    shy_radius = 3.5,
    roam_radius = 6,
    suffocate_every = 4.0,  -- seconds out of water per point of damage
    school = {3, 6},
    variants = {
        {["$flank"] = "entities/mw_fish_perch", ["$back"] = "entities/mw_fish_perch_back",
         ["$fin"] = "entities/mw_fish_perch_fin"},
        {["$flank"] = "entities/mw_fish_trout", ["$back"] = "entities/mw_fish_trout_back",
         ["$fin"] = "entities/mw_fish_trout_fin"},
        {["$flank"] = "entities/mw_fish_carp", ["$back"] = "entities/mw_fish_carp_back",
         ["$fin"] = "entities/mw_fish_carp_fin"},
        {["$flank"] = "entities/mw_fish_roach", ["$back"] = "entities/mw_fish_roach_back",
         ["$fin"] = "entities/mw_fish_roach_fin"},
    },
    loot = {
        {item = "medieval_core:raw_fish", count = 1},
    },
}

return this
