module ApplicationHelper

    # Returns the full title on a per-page basis.
    def full_title(page_title = '')
        base_title = "OwnYourData"
        if page_title.empty?
            base_title
        else
            page_title + " | " + base_title
        end
    end

# Basis-Funktionen zum Zugriff auf PIA ====================
    # verwendete Header bei GET oder POST Requests
    def defaultHeaders(token)
      { 'Accept' => '*/*',
        'Content-Type' => 'application/json',
        'Authorization' => 'Bearer ' + token }
    end

    # URL beim Zugriff auf eine Repo
    def itemsUrl(url, repo_name)
      url + '/api/repos/' + repo_name + '/items'
    end

    # Anforderung eines Tokens für ein Plugin
    def getToken(pia_url, app_key, app_secret)
        auth_url = pia_url.to_s + "/oauth/token"
        begin
            response = HTTParty.post(auth_url, 
                headers: { 'Content-Type' => 'application/json' },
                body: { client_id: app_key, 
                    client_secret: app_secret, 
                    grant_type: "client_credentials" }.to_json )
        rescue => ex
            response = nil
        end
        if response.nil?
            nil
        else
            response.parsed_response["access_token"].to_s
        end
    end

    def decrypt_message(message, keyStr)
        begin
            cipher = [JSON.parse(message)["value"]].pack('H*')
            nonce = [JSON.parse(message)["nonce"]].pack('H*')
            keyHash = RbNaCl::Hash.sha256(keyStr.force_encoding('ASCII-8BIT'))
            private_key = RbNaCl::PrivateKey.new(keyHash)
            authHash = RbNaCl::Hash.sha256('auth'.force_encoding('ASCII-8BIT'))
            auth_key = RbNaCl::PrivateKey.new(authHash).public_key
            box = RbNaCl::Box.new(auth_key, private_key)
            box.decrypt(nonce, cipher)
        rescue
            nil
        end
    end

    # Hash mit allen App-Informationen zum Zugriff auf PIA
    def setupApp(pia_url, app_key, app_secret)
      token = getToken(pia_url, app_key, app_secret)
      { "pia_url"    => pia_url,
        "app_key"    => app_key,
        "app_secret" => app_secret,
        "token"      => token }
    end

    def getWriteKey(app, repo)
        headers = defaultHeaders(app["token"])
        repo_url = app["pia_url"] + '/api/repos/' + repo + '/pub_key'
        response = HTTParty.get(repo_url, headers: headers).parsed_response
        if response.key?("public_key")
            response["public_key"]
        else
            nil
        end
    end

    def getReadKey(app)
        headers = defaultHeaders(app["token"])
        user_url = app["pia_url"] + '/api/users/current'
        response = HTTParty.get(user_url, headers: headers).parsed_response
        if response.key?("password_key")
            decrypt_message(response["password_key"], app["password"])
        else
            nil
        end
    end

    # Lese und CRUD Operationen für ein Plugin (App) ==========
    # Daten aus PIA lesen
    def readRawItems(app, repo_url)
        headers = defaultHeaders(app["token"])
        url_data = repo_url + '?size=2000'
        response = HTTParty.get(url_data, headers: headers)
        response_parsed = response.parsed_response
        if response_parsed.nil? or 
                response_parsed == "" or
                response_parsed.include?("error")
            nil
        else
            recs = response.headers["total-count"].to_i
            if recs > 2000
                (2..(recs/2000.0).ceil).each_with_index do |page|
                    url_data = repo_url + '?page=' + page.to_s + '&size=2000'
                    subresp = HTTParty.get(url_data,
                        headers: headers).parsed_response
                    response_parsed = response_parsed + subresp
                end
                response_parsed
            else
                response_parsed
            end
        end
    end

    def oydDecrypt(app, repo_url, data)
        private_key = getReadKey(app)
        if private_key.nil?
            nil
        else
            response = []
            data.each do |item|
                retVal = decrypt_message(item.to_s, private_key)
                retVal = JSON.parse(retVal)
                retVal["id"] = JSON.parse(item)["id"]
                response << retVal
            end
            response
        end
    end

    def readItems(app, repo_url)
        if app.nil? || app == ""
            nil
        else
            respData = readRawItems(app, repo_url)
            if respData.nil?
                nil
            elsif respData.length == 0
                {}
            else
                data = JSON.parse(respData.first)
                if data.key?("version")
                    oydDecrypt(app, repo_url, respData)
                else
                    data
                end
            end
        end
    end

    def writeOydItem(app, repo_url, item)
        public_key_string = getWriteKey(app, "oyd.diary.mood")
        public_key = [public_key_string].pack('H*')
        authHash = RbNaCl::Hash.sha256('auth'.force_encoding('ASCII-8BIT'))
        auth_key = RbNaCl::PrivateKey.new(authHash)
        box = RbNaCl::Box.new(public_key, auth_key)
        nonce = RbNaCl::Random.random_bytes(box.nonce_bytes)
        message = item.to_json
        msg = message.force_encoding('ASCII-8BIT')
        cipher = box.encrypt(nonce, msg)
        oyd_item = { "value" => cipher.unpack('H*')[0],
                     "nonce" => nonce.unpack('H*')[0],
                     "version" => "0.4" }
        writeItem(app, repo_url, oyd_item)
    end

    # Daten in PIA schreiben
    def writeItem(app, repo_url, item)
      headers = defaultHeaders(app["token"])
      data = item.to_json
      response = HTTParty.post(repo_url,
                               headers: headers,
                               body: data)
      response
    end

    # Daten in PIA aktualisieren
    def updateItem(app, repo_url, item, id)
      headers = defaultHeaders(app["token"])
      data = id.merge(item).to_json
      response = HTTParty.post(repo_url,
                               headers: headers,
                               body: data)
      response    
    end

    # Daten in PIA löschen
    def deleteItem(app, repo_url, id)
      headers = defaultHeaders(app["token"])
      url = repo_url + '/' + id.to_s
      response = HTTParty.delete(url,
                                 headers: headers)
      # puts "Response: " + response.to_s
      response
    end

    # alle Daten einer Liste (Repo) löschen
    def deleteRepo(app, repo_url)
      allItems = readItems(app, repo_url)
      if !allItems.nil?
        allItems.each do |item|
          deleteItem(app, repo_url, item["id"])
        end
      end
    end

end
