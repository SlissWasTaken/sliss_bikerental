local Config = {}

Config.RefundPercentage = 0.5

Config.Locations = {
    {
        coords = vec3(-1249.9249, -589.0396, 27.5138),
        cost   = 15, -- every minute
        distance = 25.0,
        drawdistance = 2.5,
        spawnPoints = {
            { coords = vec3(-1258.1871, -577.7612, 28.3134), heading = 212.13 },
            { coords = vec3(-1261.2024, -574.0928, 28.6396), heading = 223.32 },
        },
        model  = 'tribike',
        blip   = { sprite = 661, scale = 0.75, colour = 26, label = 'Bike rental' },
    },
}

return Config