class Account::Syncer
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def perform_sync(sync)
    Rails.logger.info("Processing balances (#{account.linked? ? 'reverse' : 'forward'})")
    import_market_data
    materialize_balances
  end

  def perform_post_sync
    account.family.auto_match_transfers!

    # Warm IncomeStatement caches so subsequent requests are fast
    # TODO: this is a temporary solution to speed up pages. Long term we'll throw a materialized view / pre-computed table
    # in for family stats.
    income_statement = IncomeStatement.new(account.family)
    Rails.logger.info("Warming IncomeStatement caches")
    income_statement.warm_caches!
  end

  private
    def materialize_balances
      strategy = account.linked? ? :reverse : :forward
      Balance::Materializer.new(account, strategy: strategy).materialize_balances
    end

    # Syncs all the exchange rates + security prices this account needs to display historical chart data
    #
    # This is a *supplemental* sync.  The daily market data sync should have already populated
    # a majority or all of this data, so this is often a no-op.
    #
    # We rescue errors here because if this operation fails, we don't want to fail the entire sync since
    # we have reasonable fallbacks for missing market data.
    def import_market_data
      Account::MarketDataImporter.new(account).import_all
    rescue => e
      Rails.logger.error("Error syncing market data for account #{account.id}: #{e.message}")
      Sentry.capture_exception(e)
    end
end
