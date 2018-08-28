# ffl_randomize_schedule.rb
#
# Randomizes the schedule in a fantasy football league.
#
# Requires:
#   1) Account with LM privileges
#   2) Tune the variables at the bottom of this file
#
# FYI this guy is a hero https://stackoverflow.com/a/51201043
#

require 'rubygems'
require 'open-uri'
require 'net/http'
require 'json'

MAX_RETRIES = 100000

# Adapted from https://stackoverflow.com/a/51201043
#
# Minimized JS he references:
#
#   function f() { return g() + g() + "-" + g() + "-" + g("4") + "-" + g((Math.floor(10 * Math.random()) % 4 + 8).toString(16)) + "-" + g() + g() + g() }
#   function g(e) { for (var t = Math.floor(65535 * Math.random()).toString(16), n = 4 - t.length; n > 0; n--) t = "0" + t; return e = ("" + e).substring(0, 4), !isNaN(parseInt(e, 16)) && e.length ? e + t.substr(e.length) : t }
#   function uuid(){return f();}
#
def generateId(extra=nil)
    t = (65535 * rand).floor.to_s(16)
    (4 - t.length).times do
        t = "0" + t
    end

    if extra
        return t.sub(/^./, extra)
    else
        return t
    end
end

def generateConversationID
    generateId + generateId + '-' + generateId + '-' + generateId('4') + '-' + generateId(((10 * rand).floor % 4 + 8).to_s(16)) + '-' + generateId + generateId + generateId
end

# This login routine is stupid. At the end of the day, you just need the espn_s2, SWID, and FFL_LM_COOKIE
# For more background read //stackoverflow.com/a/51201043
def login(username, password, league_id)
    # Step 1 - OPTIONS request to get correlation_id
    uri = URI.parse("https://registerdisney.go.com/jgc/v6/client/ESPN-ONESITE.WEB-PROD/api-key?langPref=en-US")
    request = Net::HTTP::Options.new(uri.request_uri)
    request["Access-Control-Request-Method"] = "POST"
    request["Access-Control-Request-Headers"] = "cache-control,content-type,conversation-id,correlation-id,expires,pragma"
    request["Origin"] = "https://cdn.registerdisney.go.com"

    req_options = {
        use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
    end

    correlation_id = response['correlation-id']
    conversation_id = generateConversationID

    # Step 2 - POST request to get api_key
    uri = URI.parse("https://registerdisney.go.com/jgc/v6/client/ESPN-ONESITE.WEB-PROD/api-key?langPref=en-US")
    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = 'null'
    request["Referer"] = "https://cdn.registerdisney.go.com/v2/ESPN-ONESITE.WEB-PROD/en-US?include=config,l10n,js,html&scheme=http&postMessageOrigin=http%3A%2F%2Fwww.espn.com%2Flogin%2F&cookieDomain=www.espn.com&config=PROD&logLevel=LOG&topHost=www.espn.com&cssOverride=https%3A%2F%2Fsecure.espncdn.com%2Fcombiner%2Fc%3Fcss%3Ddisneyid%2Fcore.css&responderPage=https%3A%2F%2Fwww.espn.com%2Flogin%2Fresponder%2F&buildId=16388ed5943"
    request["Content-Type"] = "application/json"
    request["conversation-id"] = conversation_id
    request["correlation-id"] = correlation_id

    req_options = {
        use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
    end

    api_key = response['api-key']

    # Step 3 - OPTIONS request to generate another correlation_id which we will throw away
    uri = URI.parse("https://ha.registerdisney.go.com/jgc/v6/client/ESPN-ONESITE.WEB-PROD/guest/login?langPref=en-US")
    request = Net::HTTP::Options.new(uri.request_uri)
    request["Access-Control-Request-Method"] = "POST"
    request["Access-Control-Request-Headers"] = "authorization,cache-control,content-type,conversation-id,correlation-id,expires,oneid-reporting,pragma"
    request["Origin"] = "https://cdn.registerdisney.go.com"

    req_options = {
        use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
    end

    # Step 4 - POST request to login
    params = {'loginValue' => username, 'password' => password}

    uri = URI.parse("https://ha.registerdisney.go.com/jgc/v6/client/ESPN-ONESITE.WEB-PROD/guest/login?langPref=en-US")
    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = params.to_json
    request["Referer"] = "https://cdn.registerdisney.go.com/v2/ESPN-ONESITE.WEB-PROD/en-US?include=config,l10n,js,html&scheme=http&postMessageOrigin=http%3A%2F%2Fwww.espn.com%2Flogin%2F&cookieDomain=www.espn.com&config=PROD&logLevel=LOG&topHost=www.espn.com&cssOverride=https%3A%2F%2Fsecure.espncdn.com%2Fcombiner%2Fc%3Fcss%3Ddisneyid%2Fcore.css&responderPage=https%3A%2F%2Fwww.espn.com%2Flogin%2Fresponder%2F&buildId=16388ed5943"
    request["content-type"] = "application/json"
    request["authorization"] = "APIKEY #{api_key}"
    request["conversation-id"] = conversation_id
    request["correlation-id"] = correlation_id
    request['oneid-reporting'] = 'eyJzb3VyY2UiOiJmYW50YXN5IiwiY29udGV4dCI6ImZhbnRhc3kifQ'
    request["Origin"] = "https://cdn.registerdisney.go.com"

    req_options = {
        use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
    end

    json_str = JSON.parse(response.body)

    cookies = "espn_s2=#{json_str['data']['s2']}; SWID=#{json_str['data']['token']['swid']}"

    # Step 5 - Get the FFL_LM_COOKIE
    uri = URI.parse("http://games.espn.com/ffl/clubhouse?leagueId=#{league_id}")
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Cookie"] = cookies

    req_options = {
        use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
    end

    response.get_fields('Set-Cookie').each do |set_cookie|
        set_cookie.split('; ').each do |cookie|
            if cookie.split('=')[0] == 'FFL_LM_COOKIE'
                cookies += "; #{cookie}"
            end
        end
    end

    cookies
end

# Takes a schedules 2D array of the form...
#
# [
#   [9, 5, 7, 3, 1, 6, 4, 8, 2, 8, 4, 1, 7]
#   [3, 4, 5, 2, 0, 9, 8, 7, 6, 6, 3, 0, 4]
#   [5, 3, 4, 1, 9, 8, 7, 6, 0, 4, 6, 9, 8]
#   [1, 2, 8, 0, 7, 4, 6, 9, 5, 9, 1, 7, 6]
#   [7, 1, 2, 9, 6, 3, 0, 5, 8, 2, 0, 8, 1]
#   [2, 0, 1, 6, 8, 7, 9, 4, 3, 7, 8, 6, 9]
#   [8, 7, 9, 5, 4, 0, 3, 2, 1, 1, 2, 5, 3]
#   [4, 6, 0, 8, 3, 5, 2, 1, 9, 5, 9, 3, 0]
#   [6, 9, 3, 7, 5, 2, 1, 0, 4, 0, 5, 4, 2]
#   [0, 8, 6, 4, 2, 1, 5, 3, 7, 3, 7, 2, 5]
# ]
#
# And submits it to the FFL site via its crufty API
#
def updateSchedule(schedules, cookies, league_id)
    weeks = schedules[0].length
    number_of_matchups = schedules.length / 2

    base_url = "http://games.espn.com/ffl/tools/lmeditschedule?leagueId=#{league_id}&matchupPeriodId="

    (1..weeks).each do |week|
        uri = URI.parse("#{base_url}#{week}")
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Cookie"] = cookies

        matchups = {
            'away0' => 0,
            'away1' => 0,
            'away2' => 0,
            'away3' => 0,
            'away4' => 0,
            'away5' => 0,
            'away6' => 0,
            'away7' => 0,
            'away8' => 0,
            'away9' => 0,
            'home0' => 0,
            'home1' => 0,
            'home2' => 0,
            'home3' => 0,
            'home4' => 0,
            'home5' => 0,
            'home6' => 0,
            'home7' => 0,
            'home8' => 0,
            'home9' => 0,
            'incoming' => 1 
        }

        unset_matchup_idx = 0

        schedules.each_with_index do |schedule, tid|
            skip = false

            (0..number_of_matchups-1).each do |matchup|
                if (matchups["home#{matchup}"] == tid + 1 ||
                    matchups["away#{matchup}"] == tid + 1 ||
                    matchups["home#{matchup}"] == schedule[week-1] + 1 ||
                    matchups["away#{matchup}"] == schedule[week-1] + 1)
                    skip = true
                end
            end

            unless skip
                # Dont let anyone always be the home team ;]
                if rand > 0.5
                    matchups["home#{unset_matchup_idx}"] = tid + 1
                    matchups["away#{unset_matchup_idx}"] = schedule[week-1] + 1
                else
                    matchups["away#{unset_matchup_idx}"] = tid + 1
                    matchups["home#{unset_matchup_idx}"] = schedule[week-1] + 1
                end
                unset_matchup_idx += 1
            end
        end

        request.body = URI.encode_www_form(matchups)

        req_options = {
            use_ssl: uri.scheme == "https",
        }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
            http.request(request)
        end
    end
end

# This figures out -- usually -- an array of arrays such that all n teams
# play all other n-1 teams exactly once. It then finds the rematches and 
# does the same thing over again. It doesn't always work, however, and so it
# needs to be wrapped in retry logic. While I find the problem of creating
# a deterministing algorithm for this interesting, it is not necessary for the
# scope of this crufty tool.
def randomizeSchedule(number_of_teams, number_of_weeks)
    retry_count = 0

    schedules = Array.new(number_of_teams)

    # Initialize schedules with empty arrays
    (0..number_of_teams-1).each do |i|
        schedules[i] = Array.new(number_of_weeks)
    end

    team_ids = (0..number_of_teams-1).to_a

    team_ids.each do |tid|
        if tid == 0
            opponents = (team_ids.shuffle - [team_ids[tid]])[0..number_of_weeks-1]

            schedules[tid] = opponents

            opponents.each_with_index do |oid, week|
                schedules[oid][week] = tid
            end
        else
            success = false

            until success do
                proposed_schedule = Array.new(number_of_weeks)

                available_opponents = (team_ids - [tid] - schedules[tid].compact).shuffle

                proposed_schedule.replace(schedules[tid])

                unassigned_idx = proposed_schedule.each_index.select{|i| proposed_schedule[i].nil?}

                unassigned_idx.each do |i|
                    proposed_schedule[i] = available_opponents.pop
                end

                success = true

                (0..number_of_weeks-1).each do |week|
                    (team_ids - [tid]).each do |oid|
                        if schedules[oid][week] == proposed_schedule[week]
                            success = false
                            retry_count += 1
                            raise if retry_count > MAX_RETRIES
                        end
                    end
                end
            end

            schedules[tid].replace(proposed_schedule)

            proposed_schedule.each_with_index do |oid, week|
                schedules[oid][week] = tid
            end
        end
    end

    schedules
end

def main
    # Variables - You should change these or it will not work very well.
    league_id       = '123456'
    username        = 'username'
    password        = 'changeme'
    number_of_teams = 10
    weeks           = 13

    cookies = login(username, password, league_id)

    # My algoritm for randomizing the schedule sometimes does not always converge.
    # This retry logic will get it there eventually.
    begin
        regular = randomizeSchedule(number_of_teams, number_of_teams - 1)
        rematch = randomizeSchedule(number_of_teams, weeks - number_of_teams + 1)
    rescue
        puts "Max retries hit... Retrying"
        retry
    end

    schedules = Array.new(number_of_teams)

    (0..number_of_teams-1).each do |tid|
        schedules[tid] = regular[tid] + rematch[tid]
    end

    # Gives you some output so you can compare vs. the actual schedule afterwards
    schedules.each do |schedule|
        puts schedule.inspect
    end

    updateSchedule(schedules, cookies, league_id)
end

main
