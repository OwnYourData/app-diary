class PagesController < ApplicationController
	include ApplicationHelper

	def diary
		pia_url = params[:PIA_URL].to_s
		if pia_url.to_s == ""
			pia_url = session[:pia_url]
			if pia_url.to_s == ""
				pia_url = cookies.signed[:pia_url]
			end
		else
			session[:pia_url] = pia_url
		end

		app_key = params[:APP_KEY].to_s
		if app_key.to_s == ""
			app_key = session[:app_key]
			if app_key.to_s == ""
				app_key = cookies.signed[:app_key]
			end
		else
			session[:app_key] = app_key
		end

		app_secret = params[:APP_SECRET].to_s
		if app_secret.to_s == ""
			app_secret = session[:app_secret]
			if app_secret.to_s == ""
				app_secret = cookies.signed[:app_secret]
			end
		else
			session[:app_secret] = app_secret
		end

		desktop = params[:desktop].to_s
		if desktop == ""
			desktop = session[:desktop]
			if desktop == ""
				desktop = false
			else
				if desktop == "1"
					desktop = true
				else
					desktop = false
				end
			end
		else
			if desktop == "1"
				desktop = true
			else
				desktop = false
			end
		end
		if desktop
			session[:desktop] = "1"
		else
			session[:desktop] = "0"
		end

		nonce = params[:NONCE].to_s
		if nonce.to_s == ""
			nonce = session[:nonce].to_s
			if nonce.to_s == ""
				nonce = cookies.signed[:nonce].to_s
			end
		else
			session[:nonce] = nonce
		end

		master_key = params[:MASTER_KEY].to_s
		if master_key.to_s == ""
			master_key = session[:master_key].to_s
			if master_key.to_s == ""
				master_key = cookies.signed[:master_key].to_s
				if master_key == ""
					nonce = ""
				end
			end
		else
			session[:master_key] = master_key
		end

		password = ""
		if nonce != ""
			begin
				# get cipher
		        nonce_url = pia_url + '/api/support/' + nonce
		        response = HTTParty.get(nonce_url)
		        if response.code == 200
		        	cipher = response.parsed_response["cipher"]
		        	cipherHex = [cipher].pack('H*')
		            nonceHex = [nonce].pack('H*')
	            	keyHash = [master_key].pack('H*')
	            	private_key = RbNaCl::PrivateKey.new(keyHash)
	            	authHash = RbNaCl::Hash.sha256('auth'.force_encoding('ASCII-8BIT'))
	            	auth_key = RbNaCl::PrivateKey.new(authHash).public_key
	            	box = RbNaCl::Box.new(auth_key, private_key)
	            	password = box.decrypt(nonceHex, cipherHex)

		        	# write to cookies in any case if NONCE is provided in URL
					cookies.permanent.signed[:pia_url] = pia_url
					cookies.permanent.signed[:app_key] = app_key
					cookies.permanent.signed[:app_secret] = app_secret
					cookies.permanent.signed[:password] = password

		        end
		    rescue
		    	
		    end
	    end
		if params[:password].to_s != ""
			password = params[:password].to_s
		end
		cookie_password = false
		if password.to_s == ""
			password = session[:password].to_s
			if password.to_s == ""
				password = cookies.signed[:password]
				if password.to_s != ""
					cookie_password = true
				end
			end
		else
			session[:password] = password
			if params[:remember].to_s == "1"
				cookies.permanent.signed[:pia_url] = pia_url
				cookies.permanent.signed[:app_key] = app_key
				cookies.permanent.signed[:app_secret] = app_secret
				cookies.permanent.signed[:password] = password
			end
		end
		@pia_url = pia_url
		@app_key = app_key
		@app_secret = app_secret

		# puts "pia_url: " + pia_url.to_s
		# puts "app_key: " + app_key.to_s
		# puts "app_secret: " + app_secret.to_s
		# puts "password: " + password.to_s

		token = getToken(pia_url, app_key, app_secret).to_s
		if token == ""
			redirect_to error_path(pia_url: pia_url)
			return
		end
		session[:token] = token

		if password.to_s == ""
			redirect_to password_path(pia_url: pia_url)
			return
		end

		app = setupApp(pia_url, app_key, app_secret)
		app["password"] = password.to_s
		if getReadKey(app).nil?
			if cookie_password
				flash[:warning] = t('general.wrongCookiePassword')
			else
				flash[:warning] = t('general.wrongPassword')
			end
			redirect_to password_path(pia_url: pia_url, app_key: app_key, app_secret: app_secret)
			return
		end
		if request.post?
			redirect_to root_path
		end

		mood_url = itemsUrl(app["pia_url"], "oyd.diary.mood")
		mood_data = readItems(app, mood_url)
		text_url = itemsUrl(app["pia_url"], "oyd.diary.text")
		text_data = readItems(app, text_url)
		all_data = {}
		today_mood = nil
		mood_data.each do |item|
			ts = item["timestamp"].to_s
			val = item["mood"].to_s
			item_date = Time.at(ts.to_i).to_date
			if item_date == Date.today
				@today_mood = val.to_i
				@today_mood_id = item["id"].to_s
			else
				if all_data[item_date.to_s].nil?
					all_data[item_date.to_s] = {mood: val, mood_id: item["id"]}
				else
					all_data[item_date.to_s][:mood] = val
					all_data[item_date.to_s][:mood_id] = item["id"]
				end
			end
		end unless mood_data.nil?

		text_data.each do |item|
			ts = item["timestamp"].to_s
			val = item["text"].to_s
			item_date = Time.at(ts.to_i).to_date
			if item_date == Date.today
				@today_text = val.to_s
				@today_text_id = item["id"].to_s
			else
				if all_data[item_date.to_s].nil?
					all_data[item_date.to_s] = {text: val, text_id: item["id"]}
				else
					all_data[item_date.to_s][:text] = val
					all_data[item_date.to_s][:text_id] = item["id"]
				end
			end
		end unless text_data.nil?
		@all_items = all_data
	end

	def error
		@pia_url = params[:pia_url]
	end

	def password
		@pia_url = params[:pia_url]
		@app_key = params[:app_key]
		@app_secret = params[:app_secret]
	end

	def set_mood
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
        moodUrl = itemsUrl(app["pia_url"], "oyd.diary.mood")
		if params[:mood] != params[:old]
			moodData = { "mood"      => params[:mood].to_i,
	           			 "timestamp" => DateTime.now.strftime('%s').to_i}
	        retVal = writeOydItem(app, moodUrl, moodData)
	    end
	    if params[:id].to_s != ""
        	deleteItem(app, moodUrl, params[:id].to_s)
        end
        redirect_to diary_path
	end

	def delete_mood
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
		moodUrl = itemsUrl(app["pia_url"], "oyd.diary.mood")
		if params[:id].to_s != ""
			deleteItem(app, moodUrl, params[:id].to_s)
		end
		redirect_to diary_path(operation: "edit")
	end

	def new_mood
		# read mood records
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
		app["password"] = session[:password]
		mood_url = itemsUrl(app["pia_url"], "oyd.diary.mood")
		mood_data = readItems(app, mood_url)

		if params[:locale] == "de"
			new_date = Date.strptime(params[:mood_date], "%d.%m.%Y")
		else
			new_date = Date.strptime(params[:mood_date], "%m/%d/%Y")
		end

		# walk through each record and if date is the same: delete & break
		mood_data.each do |item|
			ts = item["timestamp"].to_s
			item_date = Time.at(ts.to_i).to_date
			if item_date == new_date
				deleteItem(app, mood_url, item["id"].to_s)
				break
			end
		end unless mood_data.nil?

		# create new record
		moodData = { "mood"      => params[:mood_value].to_i,
           			 "timestamp" => new_date.to_datetime.strftime("%Y-%m-%dT12:00:00%z").to_datetime.to_i }
        retVal = writeOydItem(app, mood_url, moodData)

		redirect_to diary_path
	end

	def delete_text
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
        textUrl = itemsUrl(app["pia_url"], "oyd.diary.text")
        if params[:id].to_s != ""
        	deleteItem(app, textUrl, params[:id].to_s)
        end
		redirect_to diary_path(operation: "edit")
	end

	def set_text
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
        textUrl = itemsUrl(app["pia_url"], "oyd.diary.text")
		textData = { "text"      => params[:text].to_s,
	      			 "timestamp" => DateTime.now.strftime('%s').to_i}
	    retVal = writeOydItem(app, textUrl, textData)
	    if params[:orig_id].to_s != ""
	    	deleteItem(app, textUrl, params[:orig_id].to_s)
	    end
		redirect_to diary_path
	end


	def new_text
		# read text records
		app = setupApp(session[:pia_url], session[:app_key], session[:app_secret])
		app["password"] = session[:password]
		text_url = itemsUrl(app["pia_url"], "oyd.diary.text")
		text_data = readItems(app, text_url)

		if params[:locale] == "de"
			new_date = Date.strptime(params[:text_date], "%d.%m.%Y")
		else
			new_date = Date.strptime(params[:text_date], "%m/%d/%Y")
		end

		# walk through each record and if date is the same: delete & break
		text_data.each do |item|
			ts = item["timestamp"].to_s
			item_date = Time.at(ts.to_i).to_date
			if item_date == new_date
				deleteItem(app, text_url, item["id"].to_s)
				break
			end
		end unless text_data.nil?

		# create new record
		textData = { "text"      => params[:text_value],
           			 "timestamp" => new_date.to_datetime.strftime("%Y-%m-%dT12:00:00%z").to_datetime.to_i }
        retVal = writeOydItem(app, text_url, textData)

		redirect_to diary_path
	end

	def favicon
		send_file 'public/favicon.ico', type: 'image/x-icon', disposition: 'inline'
	end
	
end
