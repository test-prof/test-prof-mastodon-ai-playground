# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification do
  let_it_be(:account) { Fabricate(:account) }
  let_it_be(:status) { Fabricate(:status) }

  describe '#target_status' do
    let_it_be(:reblog) { Fabricate(:status, reblog: status) }
    let_it_be(:favourite) { Fabricate(:favourite, status: status) }
    let_it_be(:mention) { Fabricate(:mention, status: status) }

    it 'returns status for reblog activity' do
      notification = Fabricate(:notification, activity: reblog)
      expect(notification.target_status).to eq status
    end

    it 'returns status for favourite activity' do
      notification = Fabricate(:notification, activity: favourite)
      expect(notification.target_status).to eq status
    end

    it 'returns status for mention activity' do
      notification = Fabricate(:notification, activity: mention)
      expect(notification.target_status).to eq status
    end
  end

  describe '#type' do
    it 'returns correct type for different activities' do
      expect(described_class.new(activity: Status.new).type).to eq :reblog
      expect(described_class.new(activity: Mention.new).type).to eq :mention
      expect(described_class.new(activity: Favourite.new).type).to eq :favourite
      expect(described_class.new(activity: Follow.new).type).to eq :follow
    end
  end

  describe 'Setting account from activity_type' do
    it 'sets the notification from_account correctly for various activity types' do
      status = Fabricate(:status)
      expect(Fabricate.build(:notification, activity_type: 'Status', activity: status).from_account).to eq(status.account)

      follow = Fabricate(:follow)
      expect(Fabricate.build(:notification, activity_type: 'Follow', activity: follow).from_account).to eq(follow.account)

      favourite = Fabricate(:favourite)
      expect(Fabricate.build(:notification, activity_type: 'Favourite', activity: favourite).from_account).to eq(favourite.account)

      follow_request = Fabricate(:follow_request)
      expect(Fabricate.build(:notification, activity_type: 'FollowRequest', activity: follow_request).from_account).to eq(follow_request.account)

      poll = Fabricate(:poll)
      expect(Fabricate.build(:notification, activity_type: 'Poll', activity: poll).from_account).to eq(poll.account)

      report = Fabricate(:report)
      expect(Fabricate.build(:notification, activity_type: 'Report', activity: report).from_account).to eq(report.account)

      mention = Fabricate(:mention)
      expect(Fabricate.build(:notification, activity_type: 'Mention', activity: mention).from_account).to eq(mention.status.account)

      account = Fabricate(:account)
      expect(Fabricate.build(:notification, activity_type: 'Account', account: account).account).to eq(account)

      account_warning = Fabricate(:account_warning, target_account: account)
      expect(Fabricate.build(:notification, activity_type: 'AccountWarning', activity: account_warning, account: account).from_account).to eq(account)
    end
  end

  describe '.paginate_groups_by_max_id' do
    let_it_be(:notifications) do
      ['group-1', 'group-1', nil, 'group-2', nil, 'group-1', 'group-2', 'group-1']
        .map { |group_key| Fabricate(:notification, account: account, group_key: group_key) }
    end

    it 'returns the most recent notifications, only keeping one notification per group' do
      expect(described_class.without_suspended.paginate_groups_by_max_id(4).pluck(:id))
        .to eq [notifications[7], notifications[6], notifications[4], notifications[2]].pluck(:id)
    end

    it 'returns the most recent notifications with since_id' do
      expect(described_class.without_suspended.paginate_groups_by_max_id(4, since_id: notifications[4].id).pluck(:id))
        .to eq [notifications[7], notifications[6]].pluck(:id)
    end

    it 'returns the most recent notifications after max_id' do
      expect(described_class.without_suspended.paginate_groups_by_max_id(4, max_id: notifications[7].id).pluck(:id))
        .to eq [notifications[6], notifications[5], notifications[4], notifications[2]].pluck(:id)
    end
  end

  describe '.paginate_groups_by_min_id' do
    let_it_be(:notifications) do
      ['group-1', 'group-1', nil, 'group-2', nil, 'group-1', 'group-2', 'group-1']
        .map { |group_key| Fabricate(:notification, account: account, group_key: group_key) }
    end

    it 'returns the oldest notifications, only keeping one notification per group' do
      expect(described_class.without_suspended.paginate_groups_by_min_id(4).pluck(:id))
        .to eq [notifications[0], notifications[2], notifications[3], notifications[4]].pluck(:id)
    end

    it 'returns the oldest notifications, stopping at max_id' do
      expect(described_class.without_suspended.paginate_groups_by_min_id(4, max_id: notifications[4].id).pluck(:id))
        .to eq [notifications[0], notifications[2], notifications[3]].pluck(:id)
    end

    it 'returns the oldest notifications after min_id' do
      expect(described_class.without_suspended.paginate_groups_by_min_id(4, min_id: notifications[0].id).pluck(:id))
        .to eq [notifications[1], notifications[2], notifications[3], notifications[4]].pluck(:id)
    end
  end

  describe '.preload_cache_collection_target_statuses' do
    let_it_be(:mention) { Fabricate(:mention) }
    let_it_be(:reblog) { Fabricate(:status, reblog: Fabricate(:status)) }
    let_it_be(:follow) { Fabricate(:follow) }
    let_it_be(:follow_request) { Fabricate(:follow_request) }
    let_it_be(:favourite) { Fabricate(:favourite) }
    let_it_be(:poll) { Fabricate(:poll) }

    let(:notifications) do
      [
        Fabricate(:notification, type: :mention, activity: mention),
        Fabricate(:notification, type: :status, activity: status),
        Fabricate(:notification, type: :reblog, activity: reblog),
        Fabricate(:notification, type: :follow, activity: follow),
        Fabricate(:notification, type: :follow_request, activity: follow_request),
        Fabricate(:notification, type: :favourite, activity: favourite),
        Fabricate(:notification, type: :poll, activity: poll),
      ]
    end

    it 'preloads and caches target statuses correctly' do
      result = described_class.preload_cache_collection_target_statuses(notifications) do |target_statuses|
        Status.preload(:account).where(id: target_statuses.map(&:id))
      end

      expect(result[0].type).to eq :mention
      expect(result[0].target_status).to eq mention.status
      expect(result[0].target_status.association(:account)).to be_loaded

      expect(result[1].type).to eq :status
      expect(result[1].target_status).to eq status
      expect(result[1].target_status.association(:account)).to be_loaded

      expect(result[2].type).to eq :reblog
      expect(result[2].target_status).to eq reblog.reblog
      expect(result[2].target_status.association(:account)).to be_loaded

      expect(result[3].type).to eq :follow
      expect(result[3].target_status).to be_nil

      expect(result[4].type).to eq :follow_request
      expect(result[4].target_status).to be_nil

      expect(result[5].type).to eq :favourite
      expect(result[5].target_status).to eq favourite.status
      expect(result[5].target_status.association(:account)).to be_loaded

      expect(result[6].type).to eq :poll
      expect(result[6].target_status).to eq poll.status
      expect(result[6].target_status.association(:account)).to be_loaded
    end
  end
end
