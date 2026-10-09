-- Animal species definitions used by the millwright:animal component
--
-- temper:
--   passive  - flees only when hurt
--   shy      - also runs (or flies) away from a player within shy_radius,
--              unless the player holds its lure item
--   neutral  - fights back when hurt or when a player comes within aggro_radius
--   hostile  - hunts players within aggro_radius
-- habitats: chunk habitat (see fauna/spawning) -> spawn weight
local this = {}

this.cow = {
    entity = "millwright:cow",
    health = 10,
    temper = "passive",
    walk_speed = 14,      -- core:mob movement_speed while wandering
    flee_speed = 26,
    gait = 0.9,           -- gait cycles per block travelled
    wander_radius = 7,
    lure_item = "millwright:plant_fiber",
    tracks = {walk = "mw_cow_walk", idle = "mw_cow_graze"},
    loot = {
        {item = "millwright:raw_beef", min = 1, max = 3},
        {item = "millwright:hide", min = 1, max = 2},
    },
    herd = {2, 4},
    habitats = {plains = 3, forest = 1},
}

this.chicken = {
    entity = "millwright:chicken",
    health = 4,
    temper = "passive",
    walk_speed = 12,
    flee_speed = 24,
    gait = 2.5,
    wander_radius = 5,
    lure_item = "millwright:berries",
    tracks = {walk = "mw_chicken_walk", idle = "mw_chicken_peck", air = "mw_chicken_flap"},
    loot = {
        {item = "millwright:raw_chicken", count = 1},
        {item = "millwright:feather", min = 0, max = 2},
    },
    herd = {2, 5},
    habitats = {plains = 2, forest = 1.5},
    -- seconds between eggs
    lay_interval = {300, 600},
    lay_item = "millwright:egg",
}

this.horse = {
    entity = "millwright:horse",
    health = 14,
    temper = "shy",
    shy_radius = 7,
    walk_speed = 16,
    flee_speed = 40,
    gait = 0.7,
    wander_radius = 9,
    lure_item = "millwright:plant_fiber",
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
        {item = "millwright:raw_meat", min = 2, max = 4},
        {item = "millwright:hide", min = 1, max = 3},
    },
    herd = {3, 6},
    habitats = {plains = 2.5},
}

this.brown_bear = {
    entity = "millwright:brown_bear",
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
        {item = "millwright:raw_meat", min = 3, max = 5},
        {item = "millwright:fur", min = 1, max = 2},
    },
    herd = {1, 1},
    predator = true,
    habitats = {forest = 0.5, taiga = 0.8},
}

this.polar_bear = {
    entity = "millwright:polar_bear",
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
        {item = "millwright:raw_meat", min = 3, max = 6},
        {item = "millwright:fur", min = 2, max = 3},
    },
    herd = {1, 2},
    predator = true,
    habitats = {tundra = 0.8},
}

this.squirrel = {
    entity = "millwright:squirrel",
    health = 3,
    temper = "shy",
    shy_radius = 6,
    walk_speed = 16,
    flee_speed = 34,
    gait = 1.8,
    wander_radius = 6,
    hop = true,           -- moves in small jumps
    lure_item = "millwright:berries",
    tracks = {walk = "mw_squirrel_hop", idle = "mw_squirrel_sit"},
    loot = {
        {item = "millwright:raw_game", count = 1},
        {item = "millwright:fur", min = 0, max = 1},
    },
    herd = {1, 3},
    near_trees = true,
    habitats = {forest = 2, taiga = 2},
}

-- birds: walk/peck on the ground, take off when startled or bored, fly
-- between a few waypoints and land on the ground or on a tree crown
this.crow = {
    entity = "millwright:crow",
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
        {item = "millwright:raw_game", count = 1},
        {item = "millwright:feather", min = 1, max = 2},
    },
    herd = {3, 6},
    habitats = {plains = 1.2, forest = 0.8, taiga = 0.8, tundra = 0.4, desert = 0.4},
}

this.parrot = {
    entity = "millwright:parrot",
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
        {item = "millwright:raw_game", count = 1},
        {item = "millwright:feather", min = 1, max = 3},
    },
    herd = {2, 4},
    habitats = {tropics = 3},
}

this.owl = {
    entity = "millwright:owl",
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
        {item = "millwright:raw_game", count = 1},
        {item = "millwright:feather", min = 1, max = 3},
    },
    herd = {1, 1},
    near_trees = true,
    habitats = {taiga = 0.7, forest = 0.6},
}

return this
