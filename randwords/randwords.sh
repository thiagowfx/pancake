#!/usr/bin/env bash
set -euo pipefail

usage() {
    local cmd
    cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS]

Generate random word combinations similar to Docker container names and DuckDuckGo
disposable email addresses.

This script generates memorable random word combinations from embedded wordlists.
Perfect for naming containers, projects, or generating disposable identifiers.

OPTIONS:
    -n, --num NUM          Number of words to generate (default: 2)
    -s, --separator CHAR   Word separator (default: -)
    -N, --number           Append random number suffix (1-9999)
    -c, --capitalize       Capitalize first letter of each word
    -l, --min-len NUM      Minimum word length (default: 4)
    -L, --max-len NUM      Maximum word length (default: 10)
    -r, --repeat NUM       Generate multiple outputs, one per line (default: 1)
    -t, --type TYPE        Word style: 'docker' (adj+noun pattern) or 'random'
                           (default: docker)
    -h, --help             Show this help message and exit

EXAMPLES:
    $cmd                         Output: happy-dolphin
    $cmd -n 3                    Output: happy-dolphin-brave
    $cmd -s _                    Output: happy_dolphin
    $cmd -N                      Output: happy-dolphin-42
    $cmd -c -n 3 -N              Output: Happy-Dolphin-Brave-42
    $cmd -r 3                    Output 3 random names
    $cmd -t random -n 3          Output random words from wordlists
    $cmd --min-len 3 --max-len 8 Constrain word lengths
    $cmd -t docker -n 4          Output: happy-dolphin-brave-tiger

WORD STYLES:
    docker    Alternates adjectives and nouns (e.g., adjective-noun-adjective)
    random    Selects words randomly without pattern enforcement

EXIT CODES:
    0    Success
    1    Error (invalid arguments, no words matching criteria, etc.)
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

main() {
    local num_words=2
    local separator="-"
    local add_number=false
    local capitalize=false
    local min_len=4
    local max_len=10
    local repeat=1
    local word_type="docker"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --num)
                if [[ -z "${2:-}" ]] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --num requires a positive integer"
                    exit 1
                fi
                num_words="$2"
                shift 2
                ;;
            -s | --separator)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --separator requires a value"
                    exit 1
                fi
                if [[ ${#2} -ne 1 ]]; then
                    echo "Error: --separator must be a single character"
                    exit 1
                fi
                separator="$2"
                shift 2
                ;;
            -N | --number)
                add_number=true
                shift
                ;;
            -c | --capitalize)
                capitalize=true
                shift
                ;;
            -l | --min-len)
                if [[ -z "${2:-}" ]] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --min-len requires a positive integer"
                    exit 1
                fi
                min_len="$2"
                shift 2
                ;;
            -L | --max-len)
                if [[ -z "${2:-}" ]] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --max-len requires a positive integer"
                    exit 1
                fi
                max_len="$2"
                shift 2
                ;;
            -r | --repeat)
                if [[ -z "${2:-}" ]] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --repeat requires a positive integer"
                    exit 1
                fi
                repeat="$2"
                shift 2
                ;;
            -t | --type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --type requires a value"
                    exit 1
                fi
                case "$2" in
                    docker|random)
                        word_type="$2"
                        ;;
                    *)
                        echo "Error: --type must be 'docker' or 'random'"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -*)
                echo "Error: Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                echo "Error: Unexpected argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ $min_len -gt $max_len ]]; then
        echo "Error: --min-len cannot be greater than --max-len"
        exit 1
    fi

    get_adjectives() {
        local -a adjectives=(
            # keep-sorted start
            able
            acid
            angry
            baby
            back
            bad
            baggy
            bald
            bare
            batty
            beige
            big
            bitter
            bland
            blue
            blunt
            bold
            bony
            brave
            brief
            bright
            broad
            brown
            busy
            calm
            cheap
            cheeky
            clean
            clear
            clever
            cold
            cool
            crisp
            crooked
            cruel
            curly
            cute
            damp
            dark
            dead
            dear
            deep
            dry
            dull
            dusty
            eager
            early
            easy
            faint
            fair
            fancy
            fast
            fat
            few
            fierce
            fine
            firm
            flat
            fluffy
            free
            fresh
            front
            full
            funny
            fuzzy
            gentle
            ghostly
            giant
            glad
            gold
            good
            grand
            great
            green
            grey
            grim
            grumpy
            hairy
            happy
            hard
            harsh
            heady
            heavy
            high
            hollow
            holy
            hot
            huge
            hungry
            hurt
            icy
            ill
            jolly
            keen
            kind
            large
            late
            lazy
            lean
            left
            light
            little
            long
            loose
            loud
            low
            mad
            main
            mean
            meek
            mellow
            mild
            moist
            naive
            narrow
            nasty
            neat
            nice
            noble
            noisy
            odd
            old
            pale
            pink
            plain
            plump
            poor
            proud
            puzzled
            quick
            quiet
            rare
            rash
            ready
            red
            rich
            ripe
            rude
            sad
            safe
            saintly
            salty
            sane
            scary
            sensitive
            sharp
            short
            silly
            slim
            slimy
            slow
            small
            smart
            smooth
            soft
            sour
            spicy
            splendid
            spotty
            square
            stale
            stark
            stiff
            still
            strange
            strong
            stupid
            sweet
            swift
            tall
            tame
            tart
            tasty
            tender
            tense
            thin
            tight
            tiny
            tough
            tricky
            twin
            ugly
            upper
            upset
            vague
            vast
            vivid
            warm
            weak
            weary
            wet
            white
            wild
            wise
            witty
            wobbly
            woeful
            wonderful
            worried
            wrong
            young
            zealous
            # keep-sorted end
        )
        printf '%s\n' "${adjectives[@]}"
    }

    get_nouns() {
        local -a nouns=(
            # keep-sorted start
            aardvark
            albatross
            alligator
            alpaca
            ant
            antelope
            apple
            archer
            armadillo
            arrow
            artist
            astronaut
            badger
            baker
            balloon
            bamboo
            banana
            bandit
            barracuda
            bassoon
            beaver
            bee
            beetle
            bell
            berry
            bird
            bison
            blackberry
            blimp
            boat
            bobcat
            book
            border
            boulder
            bowl
            boxer
            brain
            brand
            bread
            brick
            bridge
            broker
            broom
            brush
            bubble
            buck
            buffalo
            bug
            bunny
            butterfly
            button
            cabbage
            cactus
            cake
            camera
            canal
            candle
            cannon
            canoe
            canvas
            canyon
            carpenter
            carrot
            cartoon
            castle
            cat
            caterpillar
            cattle
            centaur
            century
            cereal
            chameleon
            chance
            chandelier
            channel
            cheetah
            cherry
            chicken
            chimpanzee
            chocolate
            cicada
            circle
            circus
            citrus
            clam
            clarinet
            cliff
            clock
            cloud
            clown
            club
            coast
            coconut
            code
            coffee
            coin
            comet
            compass
            computer
            cone
            cookie
            cooper
            copper
            coral
            cosmos
            cotton
            cougar
            cow
            coyote
            crab
            crane
            crayon
            creek
            cricket
            crocodile
            crow
            cucumber
            cup
            curio
            cyclone
            daisy
            dancer
            deer
            desert
            diamond
            dingo
            dinosaur
            dolphin
            donkey
            dragon
            dragonfly
            dream
            drone
            drum
            duck
            eagle
            earring
            echo
            elephant
            elf
            elk
            engine
            epoxy
            espresso
            expert
            falcon
            feather
            ferret
            fiction
            fig
            finger
            firefish
            flame
            flamingo
            flash
            flute
            fly
            fog
            fox
            frog
            galaxy
            gazelle
            gear
            gecko
            gem
            ghost
            gibbon
            gift
            giraffe
            glass
            globe
            glove
            gnome
            goat
            goldfish
            goose
            gopher
            gorilla
            grape
            grass
            grasshopper
            gremlin
            griffin
            grove
            guitar
            gull
            guru
            halibut
            halo
            hamster
            harbor
            hawk
            hedgehog
            heron
            hippo
            honey
            hornet
            horse
            hummingbird
            hunter
            hurdle
            husky
            hyena
            ibex
            iguana
            illusion
            ink
            insect
            instructor
            iris
            iron
            island
            jackal
            jaguar
            jar
            jellyfish
            jewel
            jigsaw
            joker
            juggler
            jungle
            kangaroo
            kebab
            kettle
            key
            kingfisher
            kite
            kitten
            kiwi
            koala
            koi
            labradoodle
            lamp
            lark
            lasagna
            leech
            lemon
            leopard
            light
            lightbulb
            lightning
            lion
            llama
            lobster
            locust
            lorikeet
            lotus
            luna
            lynx
            macaw
            magnet
            mallard
            mango
            maple
            marble
            marlin
            marsupial
            martyr
            mask
            maverick
            meadow
            meerkat
            melon
            metal
            milk
            miner
            mink
            mirage
            moat
            moisture
            mongoose
            monkey
            monolith
            monsoon
            moose
            mosquito
            moth
            mountain
            mouse
            mule
            museum
            musician
            musk
            myth
            nail
            napkin
            narwhal
            nebula
            needle
            net
            newt
            nightingale
            nightmare
            ninja
            noble
            nomad
            noodle
            notebook
            nut
            oak
            oasis
            oats
            ocelot
            octopus
            olive
            onion
            opera
            opossum
            optician
            orange
            orca
            orchid
            otter
            owl
            oyster
            paddle
            painter
            panda
            panther
            paradox
            parakeet
            parrot
            pasta
            pastry
            peacock
            peanut
            pear
            pearl
            pebble
            pencil
            penguin
            perch
            petrel
            phantom
            phone
            piano
            pickerel
            pig
            pigeon
            pike
            piranha
            pixel
            planet
            plankton
            plato
            platypus
            plume
            pocket
            poet
            polo
            pond
            pony
            porcupine
            possum
            potato
            prairie
            prism
            pug
            puma
            puppet
            quail
            quark
            queen
            quill
            quilt
            rabbit
            raccoon
            radish
            raft
            rainbow
            raptor
            raven
            ray
            razor
            rebel
            reindeer
            rhino
            riddle
            ring
            river
            roadrunner
            robot
            rock
            rocket
            rooster
            rose
            ruby
            runner
            sailfish
            salamander
            salmon
            sampler
            sand
            sandwich
            sapphire
            satellite
            satyr
            saxophone
            scallop
            scarab
            scavenger
            school
            scorpion
            sculptor
            seahorse
            seal
            search
            secret
            seed
            shark
            sheep
            sherpa
            shield
            shrimp
            shrub
            siren
            skate
            sketch
            skunk
            sky
            slug
            smoke
            snail
            snake
            snipe
            snooze
            snow
            snowflake
            soap
            soccer
            sodium
            solar
            solstice
            song
            sparrow
            sphinx
            spider
            spike
            spoon
            squash
            squid
            squirrel
            stage
            star
            starfish
            stork
            storm
            story
            straw
            strobe
            studio
            submarine
            sugar
            sun
            sunrise
            sunset
            surgeon
            swallow
            swan
            sword
            table
            taco
            tactician
            tail
            tapir
            target
            tarsier
            taste
            teacher
            teak
            teapot
            telescope
            tenor
            tent
            tern
            thunder
            tiger
            tornado
            toucan
            toy
            trader
            tree
            trek
            trident
            trout
            trumpet
            tulip
            tuna
            turkey
            turquoise
            turtle
            twig
            unicorn
            union
            vampire
            vanilla
            vase
            veteran
            vicuna
            video
            violin
            viper
            virus
            vixen
            volcano
            vulture
            walrus
            wanderer
            wasp
            watch
            watermelon
            weasel
            web
            whale
            whippet
            whitecap
            widget
            widow
            wilderness
            willow
            window
            windstorm
            wing
            wolf
            wombat
            wonder
            wood
            woodpecker
            wool
            writer
            xenophobe
            yak
            yew
            zebra
            zephyr
            zinc
            zombie
            zoo
            zoom
            zucchini
            # keep-sorted end
        )
        printf '%s\n' "${nouns[@]}"
    }

    get_all_words() {
        get_adjectives
        get_nouns
    }

    get_random_words() {
        local count="$1"
        local type="$2"
        local words=()

        if [[ "$type" == "docker" ]]; then
            local use_adjectives=true
            local -a filtered_adjectives=()
            local -a filtered_nouns=()

            while IFS= read -r word; do
                [[ -z "$word" ]] && continue
                [[ ${#word} -ge $min_len ]] && [[ ${#word} -le $max_len ]] && \
                    filtered_adjectives+=("$word")
            done < <(get_adjectives)

            while IFS= read -r word; do
                [[ -z "$word" ]] && continue
                [[ ${#word} -ge $min_len ]] && [[ ${#word} -le $max_len ]] && \
                    filtered_nouns+=("$word")
            done < <(get_nouns)

            local adj_count=${#filtered_adjectives[@]}
            local noun_count=${#filtered_nouns[@]}

            if [[ $adj_count -eq 0 ]] || [[ $noun_count -eq 0 ]]; then
                echo "Error: No words found matching length criteria"
                exit 1
            fi

            for ((i=0; i<count; i++)); do
                if [[ "$use_adjectives" == true ]]; then
                    local idx=$((RANDOM % adj_count))
                    words+=("${filtered_adjectives[$idx]}")
                    use_adjectives=false
                else
                    local idx=$((RANDOM % noun_count))
                    words+=("${filtered_nouns[$idx]}")
                    use_adjectives=true
                fi
            done
        else
            local -a filtered_words=()

            while IFS= read -r word; do
                [[ -z "$word" ]] && continue
                [[ ${#word} -ge $min_len ]] && [[ ${#word} -le $max_len ]] && \
                    filtered_words+=("$word")
            done < <(get_all_words)

            local word_count=${#filtered_words[@]}

            if [[ $word_count -eq 0 ]]; then
                echo "Error: No words found matching length criteria"
                exit 1
            fi

            for ((i=0; i<count; i++)); do
                local idx=$((RANDOM % word_count))
                words+=("${filtered_words[$idx]}")
            done
        fi

        printf '%s\n' "${words[@]}"
    }

    capitalize_word() {
        local word="$1"
        echo "${word^}"
    }

    for ((r=0; r<repeat; r++)); do
        local -a words
        readarray -t words < <(get_random_words "$num_words" "$word_type")

        if [[ "$capitalize" == true ]]; then
            for i in "${!words[@]}"; do
                words[i]=$(capitalize_word "${words[i]}")
            done
        fi

        local result
        result=$(IFS="$separator"; echo "${words[*]}")

        if [[ "$add_number" == true ]]; then
            local random_num=$((RANDOM % 9999 + 1))
            result="${result}${separator}${random_num}"
        fi

        echo "$result"
    done
}

main "$@"
