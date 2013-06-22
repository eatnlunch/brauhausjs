###
A beer recipe, consisting of various ingredients and metadata which
provides a calculate() method to calculate OG, FG, IBU, ABV, and a
timeline of instructions for brewing the recipe.
###
class Brauhaus.Recipe extends Brauhaus.OptionConstructor
    name: 'New Recipe'
    description: 'Recipe description'
    author: 'Anonymous Brewer'
    boilSize: 10.0
    batchSize: 20.0
    servingSize: 0.355

    steepEfficiency: 50
    steepTime: 20
    mashEfficiency: 75

    style: null

    # The IBU calculation method (tinseth or rager)
    ibuMethod: 'tinseth'

    fermentables: null
    spices: null
    yeast: null

    mash: null

    og: 0.0
    fg: 0.0
    color: 0.0
    ibu: 0.0
    abv: 0.0
    price: 0.0

    # Bitterness to gravity ratio
    buToGu: 0.0
    # Balance value (http://klugscheisserbrauerei.wordpress.com/beer-balance/)
    bv: 0.0

    ogPlato: 0.0
    fgPlato: 0.0
    abw: 0.0
    realExtract: 0.0
    calories: 0.0

    bottlingTemp: 0.0
    bottlingPressure: 0.0

    primaryDays: 14.0
    primaryTemp: 20.0
    secondaryDays: 0.0
    secondaryTemp: 0.0
    tertiaryDays: 0.0
    tertiaryTemp: 0.0
    agingDays: 14
    agingTemp: 20.0

    brewDayDuration: null

    # A mapping of values used to build a recipe timeline / instructions
    timelineMap: null

    constructor: (options) ->
        @fermentables = []
        @spices = []
        @yeast = []

        super(options)

    # Get the batch size in gallons
    batchSizeGallons: ->
        Brauhaus.litersToGallons @batchSize

    # Get the boil size in gallons
    boilSizeGallons: ->
        Brauhaus.litersToGallons @boilSize

    add: (type, values) ->
        switch type
            when 'fermentable'
                @fermentables.push new Brauhaus.Fermentable(values)
            when 'spice', 'hop'
                @spices.push new Brauhaus.Spice(values)
            when 'yeast'
                @yeast.push new Brauhaus.Yeast(values)

    # Get the total weight of grains in kg
    grainWeight: ->
        weight = 0.0

        for fermentable in @fermentables
            weight += fermentable.weight if fermentable.type() is 'grain'

        weight

    # Get the total number of whole bottles (i.e. servings)
    bottleCount: ->
        Math.floor(@batchSize / @servingSize)

    calculate: ->
        @og = 1.0
        @fg = 0.0
        @ibu = 0.0
        @price = 0.0

        earlyOg = 1.0
        mcu = 0.0
        attenuation = 0.0

        # A map of various ingredient values used to generate the timeline
        # steps below.
        @timelineMap =
            fermentables:
                mash: []
                steep: []
                boil: []
                boilEnd: []
            times: {}
            drySpice: {}
            yeast: []
        
        # Calculate gravities and color from fermentables
        for fermentable in @fermentables
            efficiency = 1.0
            addition = fermentable.addition()
            if addition is 'steep'
                efficiency = @steepEfficiency / 100.0
            else if addition is 'mash'
                efficiency = @mashEfficiency / 100.0

            mcu += fermentable.color * fermentable.weightLb() / @batchSizeGallons()

            # Update gravities
            gu = fermentable.gu(@batchSize) * efficiency
            gravity = gu / 1000.0
            @og += gravity

            if not fermentable.late
                earlyOg += gravity

            # Update recipe price with fermentable
            @price += fermentable.price()

            # Add fermentable info into the timeline map
            switch addition
                when 'boil'
                    if not fermentable.late
                        @timelineMap.fermentables.boil.push [fermentable, gu]
                    else
                        @timelineMap.fermentables.boilEnd.push [fermentable, gu]
                when 'steep'
                    @timelineMap.fermentables.steep.push [fermentable, gu]
                when 'mash'
                    @timelineMap.fermentables.mash.push [fermentable, gu]

        @color = 1.4922 * Math.pow(mcu, 0.6859)

        # Get attenuation for final gravity
        for yeast in @yeast
            attenuation = yeast.attenuation if yeast.attenuation > attenuation

            # Update recipe price with yeast
            @price += yeast.price()

            # Add yeast info into the timeline map
            @timelineMap.yeast.push yeast

        attenuation = 75.0 if attenuation is 0

        # Update final gravity based on original gravity and maximum
        # attenuation from yeast.
        @fg = @og - ((@og - 1.0) * attenuation / 100.0)

        # Update alcohol by volume based on original and final gravity
        @abv = ((1.05 * (@og - @fg)) / @fg) / 0.79 * 100.0

        # Gravity degrees plato approximations
        @ogPlato = (-463.37) + (668.72 * @og) - (205.35 * (@og * @og))
        @fgPlato = (-463.37) + (668.72 * @fg) - (205.35 * (@fg * @fg))

        # Update calories
        @realExtract = (0.1808 * @ogPlato) + (0.8192 * @fgPlato)
        @abw = 0.79 * @abv / @fg
        @calories = Math.max(0, ((6.9 * @abw) + 4.0 * (@realExtract - 0.10)) * @fg * @servingSize * 10)

        # Calculate bitterness
        for spice in @spices
            bitterness = 0.0
            time = spice.time
            if spice.aa and spice.use.toLowerCase() is 'boil'
                # Account for better utilization from pellets vs. whole
                utilizationFactor = 1.0
                if spice.form is 'pellet'
                    utilizationFactor = 1.15

                # Calculate bitterness based on chosen method
                if @ibuMethod is 'tinseth'
                    bitterness = 1.65 * Math.pow(0.000125, earlyOg - 1.0) * ((1 - Math.pow(Math.E, -0.04 * spice.time)) / 4.15) * ((spice.aa / 100.0 * spice.weight * 1000000) / @batchSize) * utilizationFactor
                    @ibu += bitterness
                else if @ibuMethod is 'rager'
                    utilization = 18.11 + 13.86 * tanh((spice.time - 31.32) / 18.27)
                    adjustment = Math.max(0, (earlyOg - 1.050) / 0.2)
                    bitterness = spice.weight * 100 * utilization * utilizationFactor * spice.aa / (@batchSize * (1 + adjustment))
                    @ibu += bitterness
                else
                    throw new Error("Unknown IBU method '#{@ibuMethod}'!")

            # Update recipe price with spice
            @price += spice.price()

            # Update timeline map with hop information
            if spice.dry()
                @timelineMap['drySpice'][time] ?= []
                @timelineMap['drySpice'][time].push([spice, bitterness])
            else
                @timelineMap['times'][time] ?= []
                @timelineMap['times'][time].push([spice, bitterness])

        # Calculate bitterness to gravity ratios
        @buToGu = @ibu / (@og - 1.000) / 1000.0

        # http://klugscheisserbrauerei.wordpress.com/beer-balance/
        rte = (0.82 * (@fg - 1.000) + 0.18 * (@og - 1.000)) * 1000.0
        @bv = 0.8 * @ibu / rte

    # Get a timeline as a list of [[time, description], ...] that can be put
    # into a list or table. If siUnits is true, then use metric units,
    # otherwise use imperial units.
    # You MUST call `calculate()` on this recipe before this method.
    timeline: (siUnits = true) ->
        timeline = []

        boilName = 'water'
        totalTime = 0
        currentTemp = Brauhaus.ROOM_TEMP
        liquidVolume = 0

        # Get a list of fermentable descriptions taking siUnits into account
        fermentableList = (items) ->
            ingredients = []

            for [fermentable, gravity] in items or []
                if siUnits
                    weight = "#{fermentable.weight.toFixed 1}kg"
                else
                    lboz = fermentable.weightLbOz()
                    weight = "#{parseInt(lboz.lb)}lb #{parseInt(lboz.oz)}oz"

                ingredients.push "#{weight} of #{fermentable.name} (#{gravity.toFixed 1} GU)"

            return ingredients

        # Get a list of spice descriptions taking siUnits into account
        spiceList = (items) ->
            ingredients = []

            for [spice, ibu] in items or []
                if siUnits
                    weight = "#{parseInt(spice.weight * 1000)}g"
                else
                    weight = "#{(spice.weightLb() * 16.0).toFixed 2}oz"

                extra = ''
                if ibu
                    extra = " (#{ibu.toFixed 1} IBU)"

                ingredients.push "#{weight} of #{spice.name}#{extra}"

            return ingredients

        if @timelineMap.fermentables.mash.length
            boilName = 'wort'

            mash = @mash
            mash ?= new Brauhaus.Mash()

            ingredients = fermentableList @timelineMap.fermentables.mash
            timeline.push [totalTime, "Begin #{mash.name} mash. Add #{ingredients.join ', '}."]

            steps = @mash.steps or [
                # Default to a basic 60 minute single-infustion mash at 68C
                new Brauhaus.MashStep
                    name: 'Saccharification'
                    type: 'Infusion'
                    time: 60
                    rampTime: Brauhaus.timeToHeat @grainWeight(), 68 - currentTemp
                    temp: 68
                    waterRatio: 2.75
            ]

            for step in steps
                strikeVolume = (step.waterRatio * @grainWeight()) - liquidVolume
                if step.temp != currentTemp and strikeVolume > 0
                    # We are adding hot or cold water!
                    strikeTemp = ((step.temp - currentTemp) * (0.4184 * @grainWeight()) / strikeVolume) + step.temp
                    timeToHeat = Brauhaus.timeToHeat strikeVolume, strikeTemp - currentTemp

                    if siUnits
                        strikeVolumeDesc = "#{strikeVolume.toFixed 1}l"
                        strikeTempDesc = "#{Math.round strikeTemp}°C"
                    else
                        strikeVolumeDesc = "#{(Brauhaus.litersToGallons(strikeVolume) * 4).toFixed 1}qts"
                        strikeTempDesc = "#{Math.round Brauhaus.cToF(strikeTemp)}°F"

                    timeline.push [totalTime, "Heat #{strikeVolumeDesc} to #{strikeTempDesc} (about #{Math.round timeToHeat} minutes)"]
                    liquidVolume += strikeVolume
                    totalTime += timeToHeat
                else if step.temp != currentTemp
                    timeToHeat = Brauhaus.timeToHeat liquidVolume, step.temp - currentTemp

                    if siUnits
                        heatTemp = "#{Math.round step.temp}°C"
                    else
                        heatTemp = "#{Math.round Brauhaus.cToF(step.temp)}°F"

                    timeline.push [totalTime, "Heat the mash to #{heatTemp} (about #{Math.round timeToHeat} minutes)"]
                    totalTime += timeToHeat

                timeline.push [totalTime, "#{step.name}: #{step.description(siUnits, @grainWeight())}."]
                totalTime += step.time
                currentTemp = step.temp - (step.time * Brauhaus.MASH_HEAT_LOSS / 60.0)

            timeline.push [totalTime, 'Remove grains from mash. This is now your wort.']
            totalTime += 5
        
        if @timelineMap.fermentables.steep.length
            boilName = 'wort'
            steepWeight = (fermentable.weight for [fermentable, gravity] in @timelineMap.fermentables.steep).reduce (x, y) -> x + y
            steepHeatTime = Brauhaus.timeToHeat steepWeight * 2.75, 68 - currentTemp
            currentTemp = 68
            liquidVolume += steepWeight * 2.75

            if siUnits
                steepVolume = "#{(steepWeight * 2.75).toFixed 1}l"
                steepTemp = "#{68}°C"
            else
                steepVolume = "#{Brauhaus.litersToGallons(steepWeight * 2.75).toFixed 1}gal"
                steepTemp = "#{Brauhaus.cToF(68).toFixed 1}°F"

            timeline.push [totalTime, "Heat #{steepVolume} to #{steepTemp} (about #{Math.round steepHeatTime} minutes)"]
            totalTime += steepHeatTime

            ingredients = fermentableList @timelineMap.fermentables.steep
            timeline.push [totalTime, "Add #{ingredients.join ', '} and steep for #{@steepTime} minutes."]
            totalTime += 20
        
        # Adjust temperature based on added water
        waterChangeRatio = Math.min(1, liquidVolume / @boilSize)
        currentTemp = (currentTemp * waterChangeRatio) + (Brauhaus.ROOM_TEMP * (1.0 - waterChangeRatio))

        if siUnits
            boilVolume = "#{@boilSize.toFixed 1}l"
        else
            boilVolume = "#{@boilSizeGallons().toFixed 1}gal"

        if @boilSize - liquidVolume < @boilSize
            action = "Top up the #{boilName} to #{boilVolume} and heat to a rolling boil"
        else
            action = "Bring #{boilVolume} to a rolling boil"

        boilTime = parseInt(Brauhaus.timeToHeat @boilSize, 100 - currentTemp)
        timeline.push [totalTime, "#{action} (about #{boilTime} minutes)."]
        totalTime += boilTime

        timesStart = totalTime

        times = (parseInt(key) for own key, value of @timelineMap.times)

        # If we have late additions and no late addition time, add it
        if @timelineMap.fermentables.boilEnd.length and 5 not in times
            @timelineMap.times[5] = []
            times.push 5

        previousSpiceTime = 0
        for time, i in times.sort((x, y) -> y - x)
            ingredients = spiceList @timelineMap.times[time]

            if i is 0
                ingredients = fermentableList(@timelineMap.fermentables.boil).concat ingredients
                previousSpiceTime = time

            totalTime += previousSpiceTime - time

            previousSpiceTime = time

            if time is 5 and @timelineMap.fermentables.boilEnd.length
                ingredients = fermentableList(@timelineMap.fermentables.boilEnd).concat ingredients

            timeline.push [totalTime, "Add #{ingredients.join ', '}"]

        totalTime += previousSpiceTime

        if siUnits
            chillTemp = "#{@primaryTemp}°C"
        else
            chillTemp = "#{Brauhaus.cToF @primaryTemp}°F"

        timeline.push [totalTime, "Flame out. Begin chilling to #{chillTemp} and aerate the cooled wort (about 20 minutes)."]
        totalTime += 20

        yeasts = (yeast.name for yeast in @yeast)

        if not yeasts.length and @primaryDays
            # No yeast given, but primary fermentation should happen...
            # Let's just use a generic "yeast" to pitch.
            yeasts = ['yeast']

        if yeasts.length
            timeline.push [totalTime, "Pitch #{yeasts.join ', '} and seal the fermenter. You should see bubbles in the airlock within 24 hours."]

        # The brew day is over! Fermenting starts now.
        @brewDayDuration = totalTime

        if not @primaryDays and not @secondaryDays and not @tertiaryDays
            timeline.push [totalTime, "Drink immediately (about #{@bottleCount()} bottles)."]
            return timeline

        totalTime += @primaryDays * 1440

        if @secondaryDays
            timeline.push [totalTime, "Move to secondary fermenter for #{Brauhaus.displayDuration(@secondaryDays * 1440, 2)}."]
            totalTime += @secondaryDays * 1440

        else if @tertiaryDays
            timeline.push [totalTime, "Move to tertiary fermenter for #{Brauhaus.displayDuration(@tertiaryDays * 1440, 2)}."]
            totalTime += @tertiaryDays * 1440
        
        primeMsg = "Prime and bottle about #{@bottleCount()} bottles."

        if @agingDays
            if siUnits
                ageTemp = "#{@agingTemp}C"
            else
                ageTemp = "#{Brauhaus.cToF @agingTemp}F"

            primeMsg += " Age at #{ageTemp} for #{@agingDays} days."

        timeline.push [totalTime, primeMsg]
        totalTime += @agingDays * 1440

        timeline.push [totalTime, 'Relax, don\'t worry and have a homebrew!']

        return timeline
