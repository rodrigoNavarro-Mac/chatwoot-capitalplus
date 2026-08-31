import { shallowMount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CadenceStatusBadge from '../CadenceStatusBadge.vue';

withFullI18n();

describe('CadenceStatusBadge.vue', () => {
  it('renders the translated label for a known status', () => {
    const wrapper = shallowMount(CadenceStatusBadge, {
      props: { status: 'pending_agent_call' },
    });

    expect(wrapper.text()).toBe('Call pending');
  });

  it('falls back to the slate color for an unknown status', () => {
    const wrapper = shallowMount(CadenceStatusBadge, {
      props: { status: 'unknown_status' },
    });

    expect(wrapper.classes().join(' ')).toContain('bg-n-slate-4');
  });

  it('renders the recovered status with the teal color', () => {
    const wrapper = shallowMount(CadenceStatusBadge, {
      props: { status: 'recovered' },
    });

    expect(wrapper.classes().join(' ')).toContain('bg-n-teal-3');
    expect(wrapper.text()).toBe('Recovered');
  });
});
