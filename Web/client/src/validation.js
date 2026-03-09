// Client-side validation for lab configurations
// Mirrors server/validation.js exactly

const SLUG_REGEX = /^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$/;
const IP_REGEX =
  /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
const CIDR_REGEX =
  /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/([0-9]|[1-2][0-9]|3[0-2])$/;

export const VALID_DOMAINS = ['Win2012R2', 'Win2016', 'Win2019'];
export const VALID_SWITCH_TYPES = ['Internal', 'Private', 'External'];
export const VALID_VM_ROLES = ['DomainController', 'MemberServer', 'Client', 'Linux'];
export const VALID_VM_OS = ['windowsServer2019', 'windowsServer2022', 'windowsServer2025', 'windowsClient', 'linux'];

export const VM_OS_LABELS = {
  windowsServer2019: 'Windows Server 2019',
  windowsServer2022: 'Windows Server 2022',
  windowsServer2025: 'Windows Server 2025',
  windowsClient: 'Windows Client',
  linux: 'Linux',
};

export function validateLabConfig(config) {
  const errors = [];
  const hasInlineDomainAdmin = !!(config?.credentials?.domainAdminUser && config?.credentials?.domainAdminPassword);

  // metadata
  if (!config.metadata) {
    errors.push({ field: 'metadata', message: 'metadata section is required' });
  } else {
    if (!config.metadata.name) {
      errors.push({ field: 'metadata.name', message: 'Lab name is required' });
    } else if (!SLUG_REGEX.test(config.metadata.name)) {
      errors.push({
        field: 'metadata.name',
        message: `Lab name '${config.metadata.name}' is invalid. Must be 3-50 chars, lowercase alphanumeric or dash, starting and ending with alphanumeric.`,
      });
    }

    if (!config.metadata.displayName || !config.metadata.displayName.trim()) {
      errors.push({ field: 'metadata.displayName', message: 'Display name is required' });
    }
  }

  // domain
  if (!config.domain) {
    errors.push({ field: 'domain', message: 'domain section is required' });
  } else {
    if (!config.domain.fqdn || !config.domain.fqdn.trim()) {
      errors.push({ field: 'domain.fqdn', message: 'domain.fqdn is required' });
    }
    if (!config.domain.netbiosName || !config.domain.netbiosName.trim()) {
      errors.push({ field: 'domain.netbiosName', message: 'domain.netbiosName is required' });
    }
    if (!config.domain.functionalLevel) {
      errors.push({ field: 'domain.functionalLevel', message: 'domain.functionalLevel is required' });
    } else if (!VALID_DOMAINS.includes(config.domain.functionalLevel)) {
      errors.push({
        field: 'domain.functionalLevel',
        message: `domain.functionalLevel must be one of: ${VALID_DOMAINS.join(', ')}`,
      });
    }
  }

  // networks
  if (!config.networks || !Array.isArray(config.networks) || config.networks.length === 0) {
    errors.push({ field: 'networks', message: 'At least one network definition is required' });
  } else {
    const networkNames = new Set();
    config.networks.forEach((net, idx) => {
      const prefix = `networks[${idx}]`;

      if (!net.name || !net.name.trim()) {
        errors.push({ field: `${prefix}.name`, message: 'Network name is required' });
      } else {
        const lowerName = net.name.toLowerCase();
        if (networkNames.has(lowerName)) {
          errors.push({ field: `${prefix}.name`, message: `Duplicate network name '${net.name}'` });
        }
        networkNames.add(lowerName);
      }

      if (!net.switchType) {
        errors.push({ field: `${prefix}.switchType`, message: 'switchType is required' });
      } else if (!VALID_SWITCH_TYPES.includes(net.switchType)) {
        errors.push({
          field: `${prefix}.switchType`,
          message: `switchType must be one of: ${VALID_SWITCH_TYPES.join(', ')}`,
        });
      }

      if (!net.subnet || !net.subnet.trim()) {
        errors.push({ field: `${prefix}.subnet`, message: 'Subnet (CIDR) is required' });
      } else if (!CIDR_REGEX.test(net.subnet)) {
        errors.push({ field: `${prefix}.subnet`, message: `'${net.subnet}' is not valid CIDR notation` });
      }

      if (net.gateway && !IP_REGEX.test(net.gateway)) {
        errors.push({ field: `${prefix}.gateway`, message: `'${net.gateway}' is not a valid IP address` });
      }

      if (net.dnsServers && Array.isArray(net.dnsServers)) {
        net.dnsServers.forEach((dns, dnsIdx) => {
          if (dns && !IP_REGEX.test(dns)) {
            errors.push({ field: `${prefix}.dnsServers[${dnsIdx}]`, message: `'${dns}' is not a valid IP address` });
          }
        });
      }
    });
  }

  // vmDefinitions
  if (!config.vmDefinitions || !Array.isArray(config.vmDefinitions) || config.vmDefinitions.length === 0) {
    errors.push({ field: 'vmDefinitions', message: 'At least one VM definition is required' });
  } else {
    const vmNames = new Set();
    let hasDomainController = false;

    config.vmDefinitions.forEach((vm, idx) => {
      const prefix = `vmDefinitions[${idx}]`;

      if (!vm.name || !vm.name.trim()) {
        errors.push({ field: `${prefix}.name`, message: 'VM name is required' });
      } else {
        const lowerName = vm.name.toLowerCase();
        if (vmNames.has(lowerName)) {
          errors.push({ field: `${prefix}.name`, message: `Duplicate VM name '${vm.name}'` });
        }
        vmNames.add(lowerName);
      }

      if (!vm.role) {
        errors.push({ field: `${prefix}.role`, message: 'VM role is required' });
      } else if (!VALID_VM_ROLES.includes(vm.role)) {
        errors.push({ field: `${prefix}.role`, message: `VM role must be one of: ${VALID_VM_ROLES.join(', ')}` });
      } else if (vm.role === 'DomainController') {
        hasDomainController = true;
      }

      if (!vm.os) {
        errors.push({ field: `${prefix}.os`, message: 'VM OS is required' });
      } else if (!VALID_VM_OS.includes(vm.os)) {
        errors.push({ field: `${prefix}.os`, message: `VM OS must be one of: ${VALID_VM_OS.join(', ')}` });
      }

      if (vm.generation === undefined || vm.generation === null) {
        errors.push({ field: `${prefix}.generation`, message: 'VM generation is required' });
      } else if (![1, 2].includes(vm.generation)) {
        errors.push({ field: `${prefix}.generation`, message: 'VM generation must be 1 or 2' });
      }

      if (vm.secureBoot && vm.generation !== 2) {
        errors.push({ field: `${prefix}.secureBoot`, message: 'secureBoot can only be enabled on Generation 2 VMs' });
      }

      if (vm.tpmEnabled && (vm.generation !== 2 || vm.os !== 'windowsClient')) {
        errors.push({
          field: `${prefix}.tpmEnabled`,
          message: 'tpmEnabled is only supported on Generation 2 windowsClient VMs',
        });
      }

      if (vm.hardware) {
        const { cpuCount, memoryMB, diskSizeGB } = vm.hardware;
        if (cpuCount !== undefined && (cpuCount < 1 || cpuCount > 16)) {
          errors.push({ field: `${prefix}.hardware.cpuCount`, message: 'cpuCount is out of range (1-16)' });
        }
        if (memoryMB !== undefined && (memoryMB < 512 || memoryMB > 65536)) {
          errors.push({ field: `${prefix}.hardware.memoryMB`, message: 'memoryMB is out of range (512-65536)' });
        }
        if (diskSizeGB !== undefined && (diskSizeGB < 20 || diskSizeGB > 2000)) {
          errors.push({ field: `${prefix}.hardware.diskSizeGB`, message: 'diskSizeGB is out of range (20-2000)' });
        }
      }

      if (!vm.network || !vm.network.trim()) {
        errors.push({ field: `${prefix}.network`, message: 'Network reference is required' });
      } else if (config.networks) {
        const networkExists = config.networks.some((net) => net.name === vm.network);
        if (!networkExists) {
          errors.push({
            field: `${prefix}.network`,
            message: `Network '${vm.network}' is not defined in the networks array`,
          });
        }
      }

      if (vm.staticIP && !IP_REGEX.test(vm.staticIP)) {
        errors.push({ field: `${prefix}.staticIP`, message: `'${vm.staticIP}' is not a valid IP address` });
      }

      if (vm.guestConfiguration?.domainJoin?.enabled === true && !vm.guestConfiguration?.domainJoin?.credentialRef && !hasInlineDomainAdmin) {
        errors.push({
          field: `${prefix}.guestConfiguration.domainJoin.credentialRef`,
          message: 'credentialRef is required when domainJoin.enabled is true unless credentials.domainAdminUser/domainAdminPassword are set',
        });
      }
    });

    if (!hasDomainController) {
      errors.push({
        field: 'vmDefinitions',
        message: 'At least one VM with role DomainController is required',
      });
    }
  }

  // globalHardwareDefaults
  if (config.globalHardwareDefaults) {
    const { cpuCount, memoryMB, diskSizeGB } = config.globalHardwareDefaults;
    if (cpuCount !== undefined && (cpuCount < 1 || cpuCount > 16)) {
      errors.push({ field: 'globalHardwareDefaults.cpuCount', message: 'cpuCount is out of range (1-16)' });
    }
    if (memoryMB !== undefined && (memoryMB < 512 || memoryMB > 65536)) {
      errors.push({ field: 'globalHardwareDefaults.memoryMB', message: 'memoryMB is out of range (512-65536)' });
    }
    if (diskSizeGB !== undefined && (diskSizeGB < 20 || diskSizeGB > 2000)) {
      errors.push({ field: 'globalHardwareDefaults.diskSizeGB', message: 'diskSizeGB is out of range (20-2000)' });
    }
  }

  if (config.credentials) {
    ['localAdminRef', 'domainAdminRef', 'dsrmRef'].forEach((fieldName) => {
      const value = config.credentials[fieldName];
      if (value && String(value).trim().length < 3) {
        errors.push({
          field: `credentials.${fieldName}`,
          message: `${fieldName} must be at least 3 characters when provided`,
        });
      }
    });

    const inlinePairs = [
      ['localAdminUser', 'localAdminPassword'],
      ['domainAdminUser', 'domainAdminPassword'],
    ];
    inlinePairs.forEach(([userField, passwordField]) => {
      const hasUser = !!String(config.credentials[userField] || '').trim();
      const hasPassword = !!String(config.credentials[passwordField] || '').trim();
      if (hasUser !== hasPassword) {
        errors.push({
          field: `credentials.${userField}`,
          message: `${userField} and ${passwordField} must be provided together when using inline credentials`,
        });
      }
    });
  }

  return { isValid: errors.length === 0, errors };
}

/** Return errors for a specific field prefix */
export function errorsForField(errors, field) {
  return errors.filter((e) => e.field === field).map((e) => e.message);
}

/** Check if any errors exist for a field prefix (supports startsWith matching) */
export function hasErrorsForPrefix(errors, prefix) {
  return errors.some((e) => e.field.startsWith(prefix));
}
