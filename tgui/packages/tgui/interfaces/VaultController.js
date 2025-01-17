import { toFixed } from 'common/math';
import { useBackend } from '../backend';
import { Button, LabeledList, ProgressBar, Section } from '../components';
import { Window } from '../layouts';

export const VaultController = (props, context) => {
  const { act, data } = useBackend(context);
  return (
    <Window width={300} height={120}>
      <Window.Content>
        <Section
          title="Состояние блокировки: "
          buttons={
            <Button
              content={data.doorstatus ? 'Заблокировано' : 'Разблокировано'}
              icon={data.doorstatus ? 'lock' : 'unlock'}
              disabled={data.stored < data.max}
              onClick={() => act('togglelock')}
            />
          }>
          <LabeledList>
            <LabeledList.Item label="Заряд">
              <ProgressBar
                value={data.stored / data.max}
                ranges={{
                  good: [1, Infinity],
                  average: [0.3, 1],
                  bad: [-Infinity, 0.3],
                }}>
                {toFixed(data.stored / 1000) +
                  ' / ' +
                  toFixed(data.max / 1000) +
                  ' kW'}
              </ProgressBar>
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
