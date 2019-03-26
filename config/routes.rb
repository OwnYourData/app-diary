Rails.application.routes.draw do
	scope "(:locale)", :locale => /en|de/ do
		root  'pages#diary'
		get   'favicon',    to: 'pages#favicon'
		match '/diary',     to: 'pages#diary',    via: 'get'
		match '/diary',     to: 'pages#diary',    via: 'post'
		match '/error',     to: 'pages#error',    via: 'get'
		match '/password',  to: 'pages#password', via: 'get'
		match '/set_mood',  to: 'pages#set_mood', via: 'get',  as: 'set_mood'
		match '/set_text',  to: 'pages#set_text', via: 'post', as: 'set_text'
		match '/new_mood',  to: 'pages#new_mood', via: 'post', as: 'new_mood'
		match '/new_text',  to: 'pages#new_text', via: 'post', as: 'new_text'
		match '/delete_mood', to: 'pages#delete_mood', via: 'get'
		match '/delete_text', to: 'pages#delete_text', via: 'get'
	end
end
