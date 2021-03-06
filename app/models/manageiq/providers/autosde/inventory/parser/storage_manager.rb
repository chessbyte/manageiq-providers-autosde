# This class is supposed to take the persister and the collector, and build a snapshot of the inventory.
# The snapshot is then compared against the DB and the DB is adjusted to fit the snapshot.
class ManageIQ::Providers::Autosde::Inventory::Parser::StorageManager < ManageIQ::Providers::Inventory::Parser
  # @return [ManageIQ::Providers::Autosde::Inventory::Collector::StorageManager]
  attr_accessor :collector

  # The main function that's supposed to build the inventory_items in persister.collection based on collector's data
  #
  # example of how to build:
  # persister.physical_storages.build(
  #     :ems_ref => "s2", :name => "Storage 3", :ems_id=>persister.manager.id
  # )#
  def parse
    physical_storage_families
    physical_storages
    storage_resources
    host_initiators
    san_addresses
    storage_services
    cloud_volumes
  end

  def physical_storage_families
    collector.physical_storage_families.each do |physical_storage_family_hash|
      persister.physical_storage_families.build(**physical_storage_family_hash)
    end
  end

  def physical_storages
    collector.physical_storages.each do |physical_storage_hash|
      system_type_uuid = physical_storage_hash.delete(:system_type_uuid)
      persister.physical_storages.build(
        :physical_storage_family => persister.physical_storage_families.lazy_find(system_type_uuid),
        **physical_storage_hash
      )
    end
  end

  def storage_resources
    collector.storage_resources.each do |storage_resource_hash|
      physical_storage_ems_ref = storage_resource_hash.delete(:storage_system_uuid)
      persister.storage_resources.build(
        **storage_resource_hash, :physical_storage => persister.physical_storages.lazy_find(physical_storage_ems_ref)
      )
    end
  end

  def san_addresses
    port_type = {
      "ISCSI"  => "IscsiAddress",
      "FC"     => "FiberChannelAddress",
      "NVMeFC" => "NvmeAddress"
    }

    collector.storage_hosts.flat_map do |host_initiator|
      host_initiator.addresses.flat_map do |address|
        persister.san_addresses.build(
          :ems_ref     => address.uuid,
          :owner       => persister.host_initiators.lazy_find(host_initiator.uuid),
          :type        => port_type[address.port_type],
          :iqn         => address.iqn,
          :chap_name   => address.chap_name,
          :chap_secret => address.chap_secret,
          :wwpn        => address.wwpn
        )
      end
    end
  end

  def host_initiators
    collector.storage_hosts.each do |host_initiator|
      persister.host_initiators.build(
        :name             => host_initiator.name,
        :ems_ref          => host_initiator.uuid,
        :physical_storage => persister.physical_storages.lazy_find(host_initiator.storage_system)
      )
    end
  end

  def storage_services
    collector.storage_services.each do |storage_service_hash|
      persister.storage_services.build(**storage_service_hash)
    end
  end

  def cloud_volumes
    collector.cloud_volumes.each do |cloud_volume_hash|
      storage_resource_uuid = cloud_volume_hash.delete(:storage_resource_uuid)
      storage_service_uuid = cloud_volume_hash.delete(:storage_service_uuid)
      persister.cloud_volumes.build(
        **cloud_volume_hash,
        :storage_resource => persister.storage_resources.lazy_find(storage_resource_uuid),
        :storage_service  => persister.storage_services.lazy_find(storage_service_uuid)
      )
    end
  end
end
