class ConnectionLogsController < ApplicationController
  skip_before_filter :verify_authenticity_token

  def create
    if ConnectionLogsController.key == params[:key]
      domain = ActiveRecord::Base.transaction do
        domain = Domain.find_by(name: params[:host])
        if domain.nil?
          domain = Domain.create!(name: params[:host])
          UpdateDomainWorker.perform_async(domain.id)
        end
        domain
      end
      ConnectionLog.create!(
        ip_address: params[:ip_address],
        domain_id: domain.id
      )

      render text: "Created"
    else
      render text: "Wrong API key", status: 401
    end
  end

  private

  def self.key
    ENV["MITMPROXY_SECRET"]
  end
end
